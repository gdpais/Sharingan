import CodexBarCore
import Foundation
import Testing

struct PlanFitWindowGroupingTests {
    private static let week = 10080
    private static let weekSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let latestReset = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func `captures group by their snapped reset and the current window comes last`() throws {
        let reset = Self.latestReset
        let previous = reset.addingTimeInterval(-Self.weekSeconds)
        let entries = [
            Self.entry(previous.addingTimeInterval(-3600), 40, reset: previous.addingTimeInterval(30)),
            Self.entry(previous.addingTimeInterval(-60), 100, reset: previous),
            Self.entry(reset.addingTimeInterval(-7200), 55, reset: reset),
            // No reset recorded: belongs to the window whose boundary follows it.
            Self.entry(reset.addingTimeInterval(-3600), 60, reset: nil),
        ]
        let grouping = try #require(PlanFit.windowGrouping(
            entries: entries,
            windowMinutes: Self.week,
            now: reset.addingTimeInterval(-600),
            maxWindows: 30))
        #expect(grouping.currentResetsAt == reset)
        #expect(grouping.windows.map(\.resetsAt) == [previous, reset])
        #expect(grouping.windows.map(\.captures.count) == [2, 2])
        #expect(grouping.windows.map { grouping.periodsBeforeCurrent($0.resetsAt) } == [1, 0])

        let summary = PlanFit.summary(
            windows: grouping.windows,
            windowMinutes: Self.week,
            now: reset.addingTimeInterval(-600))
        #expect(summary.windows.map(\.isCapped) == [true, false])
        #expect(summary.windows.map(\.isCurrent) == [false, true])
    }

    @Test
    func `windows older than the budget are left out`() throws {
        let entries = (0..<5).map { index in
            let reset = Self.latestReset.addingTimeInterval(-Double(index) * Self.weekSeconds)
            return Self.entry(reset.addingTimeInterval(-3600), Double(10 * index), reset: reset)
        }
        let grouping = try #require(PlanFit.windowGrouping(
            entries: entries,
            windowMinutes: Self.week,
            now: Self.latestReset.addingTimeInterval(-60),
            maxWindows: 3))
        #expect(grouping.windows.count == 3)
        #expect(grouping.windows.last?.resetsAt == Self.latestReset)
    }

    @Test
    func `non finite captures are dropped and percents clamp to the cap`() throws {
        let entries = [
            Self.entry(Self.latestReset.addingTimeInterval(-60), .nan, reset: Self.latestReset),
            Self.entry(Self.latestReset.addingTimeInterval(-30), 140, reset: Self.latestReset),
        ]
        let grouping = try #require(PlanFit.windowGrouping(
            entries: entries,
            windowMinutes: Self.week,
            now: Self.latestReset.addingTimeInterval(-10),
            maxWindows: 30))
        #expect(grouping.windows.count == 1)
        #expect(grouping.windows.first?.captures.map(\.usedPercent) == [100])
    }

    @Test
    func `without any reset captures fall into fixed buckets`() throws {
        let interval = 5.0 * 3600
        let base = Date(timeIntervalSince1970: interval * 1000)
        let entries = [
            Self.entry(base.addingTimeInterval(60), 20, reset: nil),
            Self.entry(base.addingTimeInterval(120), 30, reset: nil),
            Self.entry(base.addingTimeInterval(interval + 60), 50, reset: nil),
        ]
        let grouping = try #require(PlanFit.windowGrouping(
            entries: entries,
            windowMinutes: 300,
            now: base.addingTimeInterval(interval + 120),
            maxWindows: 30))
        #expect(grouping.windows.map(\.resetsAt) == [
            base.addingTimeInterval(interval),
            base.addingTimeInterval(2 * interval),
        ])
        #expect(grouping.currentResetsAt == base.addingTimeInterval(2 * interval))
    }

    @Test
    func `no grouping without a window length or captures`() {
        let entry = Self.entry(Self.latestReset, 10, reset: Self.latestReset)
        let now = Self.latestReset
        let noLength = PlanFit.windowGrouping(entries: [entry], windowMinutes: 0, now: now, maxWindows: 30)
        let noCaptures = PlanFit.windowGrouping(entries: [], windowMinutes: Self.week, now: now, maxWindows: 30)
        let noBudget = PlanFit.windowGrouping(entries: [entry], windowMinutes: Self.week, now: now, maxWindows: 0)
        #expect(noLength == nil)
        #expect(noCaptures == nil)
        #expect(noBudget == nil)
    }

    private static func entry(_ capturedAt: Date, _ usedPercent: Double, reset: Date?) -> PlanFit.HistoryEntry {
        PlanFit.HistoryEntry(capturedAt: capturedAt, usedPercent: usedPercent, resetsAt: reset)
    }
}
