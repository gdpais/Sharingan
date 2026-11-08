import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

struct PlanUtilizationHistoryChartMenuViewTests {
    @Test
    func `ollama monthly transition filters old tabs without discarding saved history`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let histories = [
            PlanUtilizationSeriesHistory(
                name: .session,
                windowMinutes: 300,
                entries: [.init(capturedAt: now, usedPercent: 20, resetsAt: nil)]),
            PlanUtilizationSeriesHistory(
                name: .weekly,
                windowMinutes: 10080,
                entries: [.init(capturedAt: now, usedPercent: 40, resetsAt: nil)]),
            PlanUtilizationSeriesHistory(
                name: .monthly,
                windowMinutes: 43200,
                entries: [.init(capturedAt: now, usedPercent: 12.5, resetsAt: nil)]),
        ]
        let savedData = try JSONEncoder().encode(histories)
        let savedHistories = try JSONDecoder().decode([PlanUtilizationSeriesHistory].self, from: savedData)
        let legacy = try OllamaUsageParser.parse(html: """
        <div><span>Session usage</span><span>20% used</span></div>
        <div><span>Weekly usage</span><span>40% used</span></div>
        """, now: now).toUsageSnapshot()
        let monthly = try OllamaUsageParser.parse(html: """
        <div><span>Monthly usage</span><span>$7.50 of $60 used</span></div>
        """, now: now).toUsageSnapshot()
        let presentation = OllamaProviderDescriptor.descriptor.presentation

        #expect(presentation.planUtilizationSeries(snapshot: legacy) == [.weekly])
        #expect(presentation.planUtilizationSeries(snapshot: monthly) == [.monthly])

        let legacyBefore = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: savedHistories,
            provider: .ollama,
            snapshot: legacy)
        #expect(legacyBefore.visibleSeries == ["weekly:10080"])
        #expect(legacyBefore.usedPercents.contains(40))

        let monthlyModel = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: legacyBefore.selectedSeries,
            histories: savedHistories,
            provider: .ollama,
            snapshot: monthly)
        #expect(monthlyModel.visibleSeries == ["monthly:43200"])
        #expect(monthlyModel.selectedSeries == "monthly:43200")
        #expect(monthlyModel.usedPercents.contains(12.5))

        let legacyAfter = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: monthlyModel.selectedSeries,
            histories: savedHistories,
            provider: .ollama,
            snapshot: legacy)
        #expect(legacyAfter == legacyBefore)
        #expect(savedHistories == histories)

        let withoutCurrentSnapshot = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: savedHistories,
            provider: .ollama)
        #expect(withoutCurrentSnapshot.visibleSeries == ["session:300", "weekly:10080", "monthly:43200"])
    }

    @Test
    func `session axis labels include the hour while longer windows show only the day`() {
        // 2026-10-06 15:00 UTC.
        let date = Date(timeIntervalSince1970: 1_791_298_800)
        let locale = Locale(identifier: "en_US")
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let session = PlanUtilizationHistoryChartMenuView._axisLabelTextForTesting(
            date: date, windowMinutes: 300, locale: locale, timeZone: utc)
        let weekly = PlanUtilizationHistoryChartMenuView._axisLabelTextForTesting(
            date: date, windowMinutes: 10080, locale: locale, timeZone: utc)
        #expect(weekly == "Oct 6")
        #expect(session.hasPrefix("Oct 6"))
        #expect(session.contains("3"))
        #expect(session.contains("PM"))
    }

    @Test
    func `remembered series is restored only while it is still visible`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let histories = [
            PlanUtilizationSeriesHistory(
                name: .session,
                windowMinutes: 300,
                entries: [.init(capturedAt: now, usedPercent: 20, resetsAt: nil)]),
            PlanUtilizationSeriesHistory(
                name: .weekly,
                windowMinutes: 10080,
                entries: [.init(capturedAt: now, usedPercent: 40, resetsAt: nil)]),
        ]
        let visible = PlanUtilizationHistoryChartMenuView.visibleSeries(
            histories: histories,
            provider: .ollama,
            snapshot: nil)
        #expect(visible.map(\.id) == ["session:300", "weekly:10080"])
        #expect(PlanUtilizationHistoryChartMenuView.restoredSeriesID("weekly:10080", visibleSeries: visible)
            == "weekly:10080")
        #expect(PlanUtilizationHistoryChartMenuView.restoredSeriesID("monthly:43200", visibleSeries: visible) == nil)
        #expect(PlanUtilizationHistoryChartMenuView.restoredSeriesID(nil, visibleSeries: visible) == nil)
    }

    @Test
    func `ollama monthly history retains a currently reported weekly lane`() throws {
        let snapshot = try OllamaUsageParser.parse(html: """
        <div><span>Monthly usage</span><span>$7.50 of $60 used</span></div>
        <div><span>Weekly usage</span><span>40% used</span></div>
        """).toUsageSnapshot()

        #expect(OllamaProviderDescriptor.descriptor.presentation.planUtilizationSeries(snapshot: snapshot)
            == [.monthly, .weekly])
    }

    @Test
    func `merged entries preserve first occurrence order while removing duplicates`() {
        let first = PlanUtilizationHistoryEntry(
            capturedAt: Date(timeIntervalSince1970: 100),
            usedPercent: 10,
            resetsAt: Date(timeIntervalSince1970: 200))
        let second = PlanUtilizationHistoryEntry(
            capturedAt: Date(timeIntervalSince1970: 300),
            usedPercent: 20,
            resetsAt: nil)

        let merged = PlanUtilizationHistoryChartMenuView.mergedEntries([
            first,
            second,
            first,
            second,
        ])

        #expect(merged == [first, second])
    }

    @Test
    func `generic primary weekly window keeps weekly history visible`() {
        let history = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 42, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [history],
            provider: .zai,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["weekly:10080"])
        #expect(model.selectedSeries == "weekly:10080")
    }

    @Test
    func `generic unknown weekly extra window does not filter saved history`() {
        let history = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(
                    id: "weekly-reset-only",
                    title: "Weekly reset",
                    window: RateWindow(
                        usedPercent: 0,
                        windowMinutes: 10080,
                        resetsAt: Date(timeIntervalSince1970: 1_700_003_600),
                        resetDescription: nil),
                    usageKnown: false),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [history],
            provider: .zed,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["weekly:10080"])
        #expect(model.selectedSeries == "weekly:10080")
    }

    @Test
    func `ollama monthly snapshot filters saved legacy windows out of the history chart`() {
        let legacyWeekly = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let legacySession = PlanUtilizationSeriesHistory(
            name: .session,
            windowMinutes: 300,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 17,
                    resetsAt: nil),
            ])
        let monthly = PlanUtilizationSeriesHistory(
            name: .monthly,
            windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 7,
                    resetsAt: Date(timeIntervalSince1970: 1_700_100_000)),
            ])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 7,
                windowMinutes: ProviderPaceCapability.monthlyWindowSentinelMinutes,
                resetsAt: Date(timeIntervalSince1970: 1_700_100_000),
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [legacyWeekly, legacySession, monthly],
            provider: .ollama,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["monthly:\(ProviderPaceCapability.monthlyWindowSentinelMinutes)"])
        #expect(model.selectedSeries == "monthly:\(ProviderPaceCapability.monthlyWindowSentinelMinutes)")
    }

    @Test
    func `ollama legacy snapshot keeps the weekly history series visible`() {
        let legacyWeekly = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 42, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: [legacyWeekly],
            provider: .ollama,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["weekly:10080"])
        #expect(model.selectedSeries == "weekly:10080")
    }

    // MARK: - Plan fit

    private static let week: TimeInterval = 7 * 24 * 60 * 60
    private static let hour: TimeInterval = 60 * 60
    private static let session: TimeInterval = 5 * 60 * 60
    private static let start = Date(timeIntervalSince1970: 1_710_000_000)

    /// One window per peak, each ending `interval` after the previous. Capped windows first reach 100%
    /// `cappedHours[index]` hours before their reset.
    private static func planFitHistory(
        name: PlanUtilizationSeriesName,
        windowMinutes: Int,
        interval: TimeInterval,
        peaks: [Double],
        cappedHours: [Int: Double] = [:]) -> PlanUtilizationSeriesHistory
    {
        var entries: [PlanUtilizationHistoryEntry] = []
        for (index, peak) in peaks.enumerated() {
            let reset = self.start.addingTimeInterval(Double(index) * interval)
            // Halfway through the window, then near its end.
            entries.append(self.entry(reset: reset, hoursBefore: interval / 2 / self.hour, usedPercent: peak / 2))
            if let hours = cappedHours[index] {
                entries.append(self.entry(reset: reset, hoursBefore: hours, usedPercent: 100))
                entries.append(self.entry(reset: reset, hoursBefore: 0.25, usedPercent: 100))
            } else {
                entries.append(self.entry(reset: reset, hoursBefore: 1, usedPercent: peak))
            }
        }
        return PlanUtilizationSeriesHistory(name: name, windowMinutes: windowMinutes, entries: entries)
    }

    private static func entry(
        reset: Date,
        hoursBefore hours: Double,
        usedPercent: Double) -> PlanUtilizationHistoryEntry
    {
        PlanUtilizationHistoryEntry(
            capturedAt: reset.addingTimeInterval(-hours * self.hour),
            usedPercent: usedPercent,
            resetsAt: reset)
    }

    private static func twelveWeekHistory() -> PlanUtilizationSeriesHistory {
        self.planFitHistory(
            name: .weekly,
            windowMinutes: 10080,
            interval: self.week,
            peaks: [40, 100, 55, 62, 70, 100, 30, 62, 80, 45, 62, 50],
            cappedHours: [1: 9, 5: 3])
    }

    @Test
    func `a twelve week history fills the chart instead of thirty fixed slots`() {
        let history = Self.twelveWeekHistory()
        // Half an hour before the twelfth week resets, so that week is still running.
        let now = Self.start.addingTimeInterval(11 * Self.week - 0.5 * Self.hour)

        let fit = PlanUtilizationHistoryChartMenuView._planFitSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: [history],
            provider: .codex,
            referenceDate: now)
        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: [history],
            provider: .codex,
            referenceDate: now)

        #expect(model.pointCount == 12)
        #expect(fit.slotCount == 12)
        #expect(fit.xDomain == -0.5...11.5)
        #expect(fit.barWidth == 9)
        #expect(model.axisIndexes == [0, 4, 7])
    }

    @Test
    func `a short history keeps a minimum slot count and sits at the trailing edge`() {
        let history = Self.planFitHistory(name: .weekly, windowMinutes: 10080, interval: Self.week, peaks: [20, 30, 40])

        let fit = PlanUtilizationHistoryChartMenuView._planFitSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: [history],
            provider: .codex,
            referenceDate: Self.start.addingTimeInterval(2 * Self.week))

        #expect(fit.slotCount == 8)
        #expect(fit.xDomain == -5.5...2.5)
        #expect(fit.barWidth == 14)
    }

    @Test
    func `weekly plan fit flags capped weeks and draws the running week as so far`() {
        let now = Self.start.addingTimeInterval(11 * Self.week - 0.5 * Self.hour)

        let fit = PlanUtilizationHistoryChartMenuView._planFitSnapshotForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: [Self.twelveWeekHistory()],
            provider: .codex,
            referenceDate: now)

        #expect(fit.cappedIndexes == [1, 5])
        #expect(fit.currentIndexes == [11])
        #expect(fit.cappedLabels == [1: "9h", 5: "3h"])
        let summary = fit.summary
        #expect(summary?.settledWindowCount == 11)
        #expect(summary?.cappedWindowCount == 2)
        #expect(summary?.medianPeakPercent == 62)
        #expect(summary?.cappedHours == 12)
        #expect(summary?.verdict == .fits)
        #expect(fit.summaryLine == "Median 62% · capped 2 of 11 weeks · 12 h capped")
        #expect(fit.verdictLine == "Your plan fits how you use it.")
    }

    @Test
    func `session plan fit reports capped sessions per week`() {
        let history = Self.planFitHistory(
            name: .session,
            windowMinutes: 300,
            interval: Self.session,
            peaks: [20, 100, 40, 100, 60, 30, 100, 50, 45, 35],
            cappedHours: [1: 1, 3: 1, 6: 1])

        let fit = PlanUtilizationHistoryChartMenuView._planFitSnapshotForTesting(
            selectedSeriesRawValue: "session:300",
            histories: [history],
            provider: .codex,
            referenceDate: Self.start.addingTimeInterval(9 * Self.session))

        #expect(fit.cappedIndexes == [1, 3, 6])
        #expect(fit.currentIndexes.isEmpty)
        #expect(fit.summary?.cadence == .session)
        #expect(fit.summary?.cappedSessionsPerWeek == 3)
        #expect(fit.summary?.verdict == .hitsCapOften)
        #expect(fit.summaryLine == "Median 48% · 3 capped sessions per week · 3 h capped")
        #expect(fit.verdictLine == "You hit the cap often.")
    }

    @Test
    func `detail line adds hours capped for a capped window`() {
        let history = Self.planFitHistory(
            name: .weekly,
            windowMinutes: 10080,
            interval: Self.week,
            peaks: [40, 50, 60, 100],
            cappedHours: [3: 9])

        let detail = PlanUtilizationHistoryChartMenuView._detailLineForTesting(
            selectedSeriesRawValue: "weekly:10080",
            histories: [history],
            provider: .codex,
            referenceDate: Self.start.addingTimeInterval(3 * Self.week))

        #expect(detail.contains("100% used"))
        #expect(detail.hasSuffix(" · 9 h capped"))
    }

    @Test
    func `quota observations have no plan fit summary`() {
        let observation = PlanUtilizationSeriesHistory(
            name: .antigravityGemini,
            windowMinutes: 0,
            entries: [
                .init(capturedAt: Self.start, usedPercent: 100, resetsAt: nil),
                .init(capturedAt: Self.start.addingTimeInterval(Self.hour), usedPercent: 40, resetsAt: nil),
            ])

        let fit = PlanUtilizationHistoryChartMenuView._planFitSnapshotForTesting(
            histories: [observation],
            provider: .antigravity,
            referenceDate: Self.start.addingTimeInterval(2 * Self.hour))

        #expect(fit.summary == nil)
        #expect(fit.summaryLine == nil)
        #expect(fit.cappedIndexes.isEmpty)
        #expect(fit.cappedLabels.isEmpty)
    }
}
