import Foundation
import Testing
@testable import CodexBarCore

struct PlanFitModelTests {
    private static let hour: TimeInterval = 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60
    private static let weekMinutes = 10080
    private static let sessionMinutes = 300
    private static let start = Date(timeIntervalSince1970: 1_710_000_000)

    /// A past window ending `index` weeks (or sessions) after `start`, with one capture per percent.
    private static func window(
        endingAfter index: Int,
        interval: TimeInterval = 7 * 24 * 60 * 60,
        peaks: [Double]) -> PlanFit.WindowInput
    {
        let resetsAt = self.start.addingTimeInterval(Double(index) * interval)
        let captures = peaks.enumerated().map { offset, percent in
            PlanFit.Capture(
                capturedAt: resetsAt.addingTimeInterval(-Double(peaks.count - offset) * self.hour),
                usedPercent: percent)
        }
        return PlanFit.WindowInput(resetsAt: resetsAt, captures: captures)
    }

    private static var farFuture: Date {
        self.start.addingTimeInterval(1000 * self.week)
    }

    // MARK: - Median

    @Test
    func `median of an odd count is the middle value`() {
        #expect(PlanFit.median([70, 10, 40]) == 40)
        #expect(PlanFit.median([5]) == 5)
    }

    @Test
    func `median of an even count averages the two middle values`() {
        #expect(PlanFit.median([10, 40, 70, 100]) == 55)
        #expect(PlanFit.median([30, 20]) == 25)
    }

    @Test
    func `median ignores non-finite values and is nil when empty`() {
        #expect(PlanFit.median([]) == nil)
        #expect(PlanFit.median([.nan, .infinity]) == nil)
        #expect(PlanFit.median([.nan, 20, 60]) == 40)
    }

    // MARK: - Windows

    @Test
    func `capped hours run from the first capture at the cap to the reset with irregular captures`() {
        let resetsAt = Self.start
        let input = PlanFit.WindowInput(resetsAt: resetsAt, captures: [
            // Out of order and unevenly spaced; the cap is first seen 9.5 hours before the reset.
            PlanFit.Capture(capturedAt: resetsAt.addingTimeInterval(-2 * Self.hour), usedPercent: 100),
            PlanFit.Capture(capturedAt: resetsAt.addingTimeInterval(-50 * Self.hour), usedPercent: 40),
            PlanFit.Capture(capturedAt: resetsAt.addingTimeInterval(-9.5 * Self.hour), usedPercent: 100),
            PlanFit.Capture(capturedAt: resetsAt.addingTimeInterval(-30 * Self.hour), usedPercent: 99.9),
        ])

        let window = PlanFit.window(input, windowMinutes: Self.weekMinutes, now: Self.farFuture)

        #expect(window.isCapped)
        #expect(window.firstCappedAt == resetsAt.addingTimeInterval(-9.5 * Self.hour))
        #expect(window.cappedHours == 9.5)
        #expect(window.peakPercent == 100)
        #expect(window.captureCount == 4)
        #expect(!window.isCurrent)
        #expect(window.isSettled)
    }

    @Test
    func `a window just under the cap is not capped`() {
        let window = PlanFit.window(
            Self.window(endingAfter: 0, peaks: [60, 99.9]),
            windowMinutes: Self.weekMinutes,
            now: Self.farFuture)

        #expect(!window.isCapped)
        #expect(window.cappedHours == 0)
        #expect(window.peakPercent == 99.9)
    }

    @Test
    func `capped hours never exceed the window length or go negative`() {
        let resetsAt = Self.start
        let early = PlanFit.window(
            PlanFit.WindowInput(resetsAt: resetsAt, captures: [
                PlanFit.Capture(capturedAt: resetsAt.addingTimeInterval(-9 * Self.hour), usedPercent: 120),
            ]),
            windowMinutes: Self.sessionMinutes,
            now: Self.farFuture)
        #expect(early.cappedHours == 5)
        #expect(early.peakPercent == 100)

        let late = PlanFit.window(
            PlanFit.WindowInput(resetsAt: resetsAt, captures: [
                PlanFit.Capture(capturedAt: resetsAt.addingTimeInterval(Self.hour), usedPercent: 100),
            ]),
            windowMinutes: Self.weekMinutes,
            now: Self.farFuture)
        #expect(late.isCapped)
        #expect(late.cappedHours == 0)
    }

    @Test
    func `the current window counts only once it has capped`() {
        let now = Self.start.addingTimeInterval(-Self.hour)
        let inProgress = PlanFit.window(
            Self.window(endingAfter: 0, peaks: [30, 50]),
            windowMinutes: Self.weekMinutes,
            now: now)
        #expect(inProgress.isCurrent)
        #expect(!inProgress.isSettled)

        let cappedEarly = PlanFit.window(
            Self.window(endingAfter: 0, peaks: [60, 100]),
            windowMinutes: Self.weekMinutes,
            now: now)
        #expect(cappedEarly.isCurrent)
        #expect(cappedEarly.isSettled)
        // Hours until the reset, since usage cannot drop before the window resets.
        #expect(cappedEarly.cappedHours == 1)
    }

    // MARK: - Verdict

    @Test
    func `a median of exactly 35 percent fits while just below is underused`() {
        #expect(PlanFit.verdict(medianPeakPercent: 35, cappedWindowCount: 0, windowCount: 8) == .fits)
        #expect(PlanFit.verdict(medianPeakPercent: 34.9, cappedWindowCount: 0, windowCount: 8) == .underused)
    }

    @Test
    func `capping exactly one window in four hits the cap often`() {
        #expect(PlanFit.verdict(medianPeakPercent: 60, cappedWindowCount: 1, windowCount: 4) == .hitsCapOften)
        #expect(PlanFit.verdict(medianPeakPercent: 60, cappedWindowCount: 3, windowCount: 12) == .hitsCapOften)
        #expect(PlanFit.verdict(medianPeakPercent: 60, cappedWindowCount: 1, windowCount: 5) == .fits)
        #expect(PlanFit.verdict(medianPeakPercent: 60, cappedWindowCount: 2, windowCount: 9) == .fits)
    }

    @Test
    func `hitting the cap often wins over a low median`() {
        #expect(PlanFit.verdict(medianPeakPercent: 10, cappedWindowCount: 1, windowCount: 4) == .hitsCapOften)
    }

    @Test
    func `fewer than four settled windows give no verdict`() {
        #expect(PlanFit.verdict(medianPeakPercent: 10, cappedWindowCount: 3, windowCount: 3) == .notEnoughHistory)
        #expect(PlanFit.verdict(medianPeakPercent: nil, cappedWindowCount: 0, windowCount: 4) == .notEnoughHistory)
    }

    // MARK: - Summary

    @Test
    func `weekly summary counts capped weeks hours and the median of settled weeks`() {
        let inputs = [
            Self.window(endingAfter: 0, peaks: [20, 40]),
            Self.window(endingAfter: 1, peaks: [70, 100, 100]),
            Self.window(endingAfter: 2, peaks: [62]),
            Self.window(endingAfter: 3, peaks: [10, 55]),
            Self.window(endingAfter: 4, peaks: [90]),
        ]
        // The last window is still running and has not capped, so it stays out of the summary.
        let now = Self.start.addingTimeInterval(4 * Self.week - Self.hour)

        let summary = PlanFit.summary(windows: inputs, windowMinutes: Self.weekMinutes, now: now)

        #expect(summary.cadence == .weekly)
        #expect(summary.windows.count == 5)
        #expect(summary.windows.map(\.isCurrent) == [false, false, false, false, true])
        #expect(summary.settledWindowCount == 4)
        #expect(summary.cappedWindowCount == 1)
        #expect(summary.medianPeakPercent == 58.5)
        #expect(summary.cappedHours == 2)
        #expect(summary.cappedSessionsPerWeek == nil)
        #expect(summary.verdict == .hitsCapOften)
    }

    @Test
    func `session summary reports capped sessions per week instead of a window count`() {
        let session = Double(Self.sessionMinutes) * 60
        // Two capped sessions over exactly five weeks of history (168 sessions of five hours).
        let inputs = [
            Self.window(endingAfter: 0, interval: session, peaks: [100]),
            Self.window(endingAfter: 1, interval: session, peaks: [40]),
            Self.window(endingAfter: 2, interval: session, peaks: [30]),
            Self.window(endingAfter: 167, interval: session, peaks: [100]),
        ]

        let summary = PlanFit.summary(windows: inputs, windowMinutes: Self.sessionMinutes, now: Self.farFuture)

        #expect(summary.cadence == .session)
        #expect(summary.settledWindowCount == 4)
        #expect(summary.cappedWindowCount == 2)
        #expect(summary.cappedSessionsPerWeek == 0.4)
        #expect(summary.verdict == .hitsCapOften)
    }

    @Test
    func `a short session history counts as one week instead of extrapolating`() {
        let session = Double(Self.sessionMinutes) * 60
        let inputs = (0..<4).map { Self.window(endingAfter: $0, interval: session, peaks: [$0 == 0 ? 100 : 30]) }

        let summary = PlanFit.summary(windows: inputs, windowMinutes: Self.sessionMinutes, now: Self.farFuture)

        #expect(summary.cappedSessionsPerWeek == 1)
        #expect(summary.cappedHours == 1)
    }

    @Test
    func `empty history has no median no rate and no verdict`() {
        let weekly = PlanFit.summary(windows: [], windowMinutes: Self.weekMinutes, now: Self.start)
        #expect(weekly.windows.isEmpty)
        #expect(weekly.settledWindowCount == 0)
        #expect(weekly.cappedWindowCount == 0)
        #expect(weekly.medianPeakPercent == nil)
        #expect(weekly.cappedHours == 0)
        #expect(weekly.verdict == .notEnoughHistory)

        let sessions = PlanFit.summary(windows: [], windowMinutes: Self.sessionMinutes, now: Self.start)
        #expect(sessions.cadence == .session)
        #expect(sessions.cappedSessionsPerWeek == nil)
        #expect(sessions.verdict == .notEnoughHistory)
    }

    @Test
    func `windows without captures stay out of the summary`() {
        let inputs = [
            PlanFit.WindowInput(resetsAt: Self.start, captures: []),
            Self.window(endingAfter: 1, peaks: [50]),
        ]

        let summary = PlanFit.summary(windows: inputs, windowMinutes: Self.weekMinutes, now: Self.farFuture)

        #expect(summary.windows.count == 2)
        #expect(summary.settledWindowCount == 1)
        #expect(summary.medianPeakPercent == 50)
    }

    @Test
    func `cadence follows the window length`() {
        #expect(PlanFit.Cadence(windowMinutes: 300) == .session)
        #expect(PlanFit.Cadence(windowMinutes: 60) == .session)
        #expect(PlanFit.Cadence(windowMinutes: 301) == .other)
        #expect(PlanFit.Cadence(windowMinutes: 10080) == .weekly)
        #expect(PlanFit.Cadence(windowMinutes: 43200) == .monthly)
        #expect(PlanFit.Cadence(windowMinutes: 1440) == .other)
        #expect(PlanFit.Cadence(windowMinutes: 0) == .other)
    }
}
