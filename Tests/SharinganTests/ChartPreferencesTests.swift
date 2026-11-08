import SharinganCore
import Foundation
import Testing
@testable import Sharingan

@MainActor
struct ChartPreferencesTests {
    private typealias Entry = CostUsageDailyReport.Entry

    // MARK: - Defaults

    @Test
    func `defaults match the charts before preferences existed`() {
        let preferences = ChartPreferences()
        #expect(preferences == .standard)
        #expect(preferences.range == .historyWindow)
        #expect(preferences.stackByModel)
        #expect(preferences.showsAverageLine)
        #expect(preferences.style == .bars)
        #expect(preferences.paletteMode == .accents)
        #expect(ChartPreferences(storage: nil) == .standard)
        #expect(ChartPreferences(storage: [:]) == .standard)
    }

    @Test
    func `unknown stored values fall back to their defaults`() {
        let preferences = ChartPreferences(storage: [
            "range": "days365",
            "stackByModel": "maybe",
            "averageLine": "false",
            "style": "pie",
            "palette": "neon",
        ])
        #expect(preferences == ChartPreferences(showsAverageLine: false))
    }

    @Test
    func `stored dictionary round trips every choice`() {
        for range in ChartPreferences.RangeOption.allCases {
            for style in ChartPreferences.Style.allCases {
                for palette in ChartPaletteMode.allCases {
                    let preferences = ChartPreferences(
                        range: range,
                        stackByModel: false,
                        showsAverageLine: false,
                        style: style,
                        paletteMode: palette)
                    #expect(ChartPreferences(storage: preferences.storage) == preferences)
                }
            }
        }
    }

    // MARK: - Persistence

    @Test
    func `preferences persist outside the synced config`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let originalConfig = try encoder.encode(settings.config)

        #expect(settings.chartPreferences == .standard)
        let chosen = ChartPreferences(range: .days7, stackByModel: false, style: .line, paletteMode: .monochrome)
        settings.setChartPreferences(chosen)
        #expect(settings.chartPreferences == chosen)

        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.chartPreferences == chosen)
        #expect(try encoder.encode(settings.config) == originalConfig)
    }

    @Test
    func `choosing the defaults stores nothing`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        settings.setChartPreferences(.standard)
        #expect(defaults.object(forKey: ChartPreferences.defaultsKey) == nil)
    }

    @Test
    func `test processes always paint with provider accents`() {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.setChartPreferences(ChartPreferences(paletteMode: .monochrome))
        #expect(ChartPaletteSetting.activeMode == .accents)
        #expect(SpendActivityPalette(colorScheme: .light).mode == .accents)
    }

    // MARK: - Range

    @Test
    func `range never plots more than the history window`() {
        #expect(ChartPreferences().plottedDays(historyDays: 30) == 30)
        #expect(ChartPreferences(range: .days7).plottedDays(historyDays: 30) == 7)
        #expect(ChartPreferences(range: .days90).plottedDays(historyDays: 30) == 30)
        #expect(ChartPreferences(range: .days30).plottedDays(historyDays: 0) == 1)
    }

    @Test
    func `a shorter range plots the last days ending today`() throws {
        let calendar = Self.utcCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        let entries = (1...30).map { Self.entry(String(format: "2026-06-%02d", $0)) }

        let week = ChartPreferences(range: .days7).plottedEntries(
            entries, historyDays: 30, now: now, calendar: calendar)
        #expect(week.map(\.date) == (24...30).map { String(format: "2026-06-%02d", $0) })

        for preferences in [ChartPreferences(), ChartPreferences(range: .days30), ChartPreferences(range: .days90)] {
            #expect(preferences.plottedEntries(entries, historyDays: 30, now: now, calendar: calendar) == entries)
        }
    }

    @Test
    func `cost history plots every day unless the range is shorter`() throws {
        let now = try #require(Self.utcCalendar.date(from: DateComponents(year: 2026, month: 6, day: 30, hour: 12)))
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: 30,
            historyDays: 30,
            daily: (1...30).map { Self.entry(String(format: "2026-06-%02d", $0)) },
            updatedAt: now)
        #expect(CostHistoryChartMenuView.plottedDaily(
            snapshot, preferences: .standard, historyDays: 30, calendar: Self.utcCalendar) == nil)
        #expect(CostHistoryChartMenuView.plottedDaily(
            snapshot,
            preferences: ChartPreferences(range: .days90),
            historyDays: 30,
            calendar: Self.utcCalendar) == nil)
        let week = CostHistoryChartMenuView.plottedDaily(
            snapshot, preferences: ChartPreferences(range: .days7), historyDays: 30, calendar: Self.utcCalendar)
        #expect(week?.count == 7)
        #expect(week?.last?.date == "2026-06-30")
    }

    // MARK: - Settings copy

    @Test
    func `settings labels name every option`() {
        SharinganLocalizationOverride.$appLanguage.withValue("en") {
            #expect(ChartPreferences.RangeOption.allCases.map(ChartPreferencesSettingsSection.rangeLabel) == [
                "History window", "Last 7 days", "Last 30 days", "Last 90 days",
            ])
            #expect(ChartPreferences.Style.allCases.map(ChartPreferencesSettingsSection.styleLabel) == ["Bars", "Line"])
            #expect(ChartPaletteMode.allCases.map(ChartPreferencesSettingsSection.paletteLabel) == [
                "Provider accents", "Colorblind-safe", "Monochrome",
            ])
        }
    }

    // MARK: - Fixtures

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func entry(_ date: String) -> Entry {
        Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 100,
            costUSD: 1,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }
}
