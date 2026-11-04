import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct SpendHourOfWeekHeatmapTests {
    @Test
    func `the grid folds every recorded hour in the range unless a day is selected`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // Thursday 2026-10-01 through Saturday 2026-10-03.
        let first = try Self.date("2026-10-01T00:00:00Z")
        let days = (0..<3).map { first.addingTimeInterval(Double($0) * 86400) }
        let now = days[2].addingTimeInterval(20 * 3600)
        let hours = [1, 9, 14]
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: ["2026-10-01", "2026-10-02", "2026-10-03"].map { Self.entry($0, cost: 3) },
            hourly: days.flatMap { day in
                hours.map { hour in
                    CostUsageHourlyEntry(
                        hour: day.addingTimeInterval(Double(hour) * 3600),
                        totalTokens: nil,
                        costUSD: 1)
                }
            },
            updatedAt: now)
        let input = SpendDashboardModel.ProviderInput(
            id: "demo-a", provider: .codex, displayName: "Demo account", snapshot: snapshot)
        func build(selectedDay: Date? = nil) throws -> SpendDashboardModel.CurrencyGroup {
            try #require(SpendDashboardModel.build(
                inputs: [input],
                reportingPeriod: .allTime,
                now: now,
                calendar: calendar,
                selectedDay: selectedDay).groups.first)
        }

        let range = try build()
        let samples = SpendTrendChartModel.hourOfWeekSamples(group: range)
        #expect(samples.count == 9)
        let model = HourOfWeekHeatmapModel(samples: samples, calendar: range.calendar)
        #expect(model.totalCost == 9)
        #expect(model.cell(weekday: 5, hour: 1)?.cost == 1)
        #expect(model.cell(weekday: 6, hour: 9)?.cost == 1)
        #expect(model.cell(weekday: 7, hour: 14)?.cost == 1)
        #expect(model.weekendShare == 3.0 / 9.0)

        // The dashboard model narrows hourly points to a selected day; the panel hides the grid then.
        let selected = try build(selectedDay: days[1])
        #expect(SpendTrendChartModel.hourOfWeekSamples(group: selected).map(\.hour) == hours.map {
            days[1].addingTimeInterval(Double($0) * 3600)
        })
    }

    @Test
    func `isolating a source and the legend use only hourly points inside the range`() throws {
        let start = try Self.date("2026-10-01T00:00:00Z")
        let end = start.addingTimeInterval(2 * 86400)
        let group = Self.group(
            providers: ["demo-a", "demo-b", "demo-c"].map(Self.provider),
            points: [
                Self.point(start.addingTimeInterval(3600), sourceID: "demo-a", cost: 1),
                Self.point(start.addingTimeInterval(3600), sourceID: "demo-b", cost: 2),
                Self.point(start.addingTimeInterval(86400 + 7200), sourceID: "demo-b", cost: 4),
                Self.point(end, sourceID: "demo-c", cost: 8),
                Self.point(start.addingTimeInterval(-3600), sourceID: "demo-c", cost: 8),
            ],
            bounds: start...end)

        #expect(SpendTrendChartModel.hourOfWeekLegendProviders(in: group).map(\.id) == ["demo-a", "demo-b"])
        #expect(SpendTrendChartModel.hourOfWeekSamples(group: group).map(\.cost) == [1, 2, 4])
        #expect(SpendTrendChartModel.hourOfWeekSamples(group: group, sourceID: "demo-b").map(\.cost) == [2, 4])
        #expect(SpendTrendChartModel.hourOfWeekSamples(group: group, sourceID: "demo-c").isEmpty)
    }

    @Test
    func `the grid calendar keeps the statistics time zone with the viewer first weekday`() throws {
        let start = try Self.date("2026-10-01T00:00:00Z")
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let group = Self.group(
            providers: [],
            points: [],
            bounds: start...start.addingTimeInterval(86400),
            timeZone: tokyo)
        let calendar = SpendTrendChartModel.hourOfWeekCalendar(
            group: group,
            firstWeekday: 2,
            locale: Locale(identifier: "en_US_POSIX"))

        #expect(calendar.timeZone == tokyo)
        #expect(calendar.firstWeekday == 2)
        #expect(HourOfWeekHeatmapModel(samples: [], calendar: calendar).weekdays == [2, 3, 4, 5, 6, 7, 1])
        #expect(SpendTrendChartModel.hourOfWeekWeekdayText(3, calendar: calendar) == "Tue")
        #expect(SpendTrendChartModel.hourOfWeekWeekdayText(1, calendar: calendar) == "Sun")
        #expect(SpendTrendChartModel.hourOfWeekWeekdayText(9, calendar: calendar) == "9")
        #expect(SpendTrendChartModel.hourOfWeekClockText(6) == "06:00")
        #expect(SpendTrendChartModel.hourOfWeekClockText(14) == "14:00")
    }

    private static func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    private static func provider(_ id: String) -> SpendDashboardModel.ProviderRow {
        SpendDashboardModel.ProviderRow(
            id: id,
            rank: 1,
            provider: .codex,
            displayName: "Demo account",
            totalTokens: nil,
            totalCost: nil,
            coveredDayCount: 0)
    }

    private static func point(_ hour: Date, sourceID: String, cost: Double) -> SpendDashboardModel.HourlyPoint {
        SpendDashboardModel.HourlyPoint(
            sourceID: sourceID,
            provider: .codex,
            providerName: "Demo account",
            hour: hour,
            cost: cost,
            stackStart: 0,
            stackEnd: cost)
    }

    private static func group(
        providers: [SpendDashboardModel.ProviderRow],
        points: [SpendDashboardModel.HourlyPoint],
        bounds: ClosedRange<Date>,
        timeZone: TimeZone = .gmt) -> SpendDashboardModel.CurrencyGroup
    {
        SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: providers,
            models: [],
            dailyPoints: [],
            totalTokens: nil,
            totalCost: nil,
            coveredDayCount: 0,
            chartDomain: bounds,
            modelHistoryCompleteness: .incomplete,
            hourlyPoints: points,
            timeZone: timeZone)
    }

    private static func entry(_ day: String, cost: Double?) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }
}
