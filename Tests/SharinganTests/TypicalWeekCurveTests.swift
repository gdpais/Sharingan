import Foundation
import Testing
@testable import SharinganCore

struct TypicalWeekCurveTests {
    @Test
    func `median and quartiles follow the past weeks at every grid point`() throws {
        let curve = try #require(TypicalWeekCurve(
            weeks: Self.pastWeeks(),
            windowMinutes: Self.weekMinutes,
            currentResetsAt: Self.reset))

        #expect(curve.weekCount == 4)
        #expect(curve.points.map(\.fraction) == [0, 0.5, 1])
        #expect(curve.points.map(\.medianUsedPercent) == [0, 25, 50])
        #expect(curve.points.map(\.lowerUsedPercent) == [0, 17.5, 35])
        #expect(curve.points.map(\.upperUsedPercent) == [0, 32.5, 65])
    }

    @Test
    func `needs enough finished weeks of the same length`() {
        let weeks = Self.pastWeeks()
        #expect(TypicalWeekCurve(
            weeks: Array(weeks.prefix(2)),
            windowMinutes: Self.weekMinutes,
            currentResetsAt: Self.reset) == nil)
        #expect(TypicalWeekCurve(weeks: weeks, windowMinutes: 300, currentResetsAt: Self.reset) == nil)
        #expect(TypicalWeekCurve(weeks: [], windowMinutes: Self.weekMinutes, currentResetsAt: Self.reset) == nil)
        #expect(TypicalWeekCurve(weeks: weeks, windowMinutes: 0, currentResetsAt: Self.reset) == nil)
    }

    @Test
    func `the week in progress and other grids never count`() throws {
        let inProgress = TypicalWeekCurve.Week(
            resetsAt: Self.reset.addingTimeInterval(90),
            windowMinutes: Self.weekMinutes,
            usedPercent: [0, 90, 100])
        let otherGrid = TypicalWeekCurve.Week(
            resetsAt: Self.reset.addingTimeInterval(-5 * Self.weekSeconds),
            windowMinutes: Self.weekMinutes,
            usedPercent: [0, 100, 100, 100])
        let nonFinite = TypicalWeekCurve.Week(
            resetsAt: Self.reset.addingTimeInterval(-6 * Self.weekSeconds),
            windowMinutes: Self.weekMinutes,
            usedPercent: [0, .nan, 100])

        let curve = try #require(TypicalWeekCurve(
            weeks: Self.pastWeeks() + [inProgress, otherGrid, nonFinite],
            windowMinutes: Self.weekMinutes,
            currentResetsAt: Self.reset))

        #expect(curve.weekCount == 4)
        #expect(curve.points.map(\.medianUsedPercent) == [0, 25, 50])
    }

    @Test
    func `aligned window maps the grid from window start to reset`() throws {
        let curve = try #require(TypicalWeekCurve(
            weeks: Self.pastWeeks(),
            windowMinutes: Self.weekMinutes,
            currentResetsAt: Self.reset))
        let start = Self.reset.addingTimeInterval(-Self.weekSeconds)

        let timeline = curve.timeline(endingAt: Self.reset, over: start...Self.reset)

        #expect(timeline.map(\.date) == [start, start.addingTimeInterval(Self.weekSeconds / 2), Self.reset])
        #expect(timeline.map(\.medianUsedPercent) == [0, 25, 50])
        #expect(timeline.map(\.lowerUsedPercent) == [0, 17.5, 35])
        #expect(timeline.map(\.upperUsedPercent) == [0, 32.5, 65])
    }

    @Test
    func `window that started mid curve is clipped and rebased at its start`() throws {
        let curve = try #require(TypicalWeekCurve(
            weeks: Self.pastWeeks(),
            windowMinutes: Self.weekMinutes,
            currentResetsAt: Self.reset))
        let curveStart = Self.reset.addingTimeInterval(-Self.weekSeconds)
        let start = curveStart.addingTimeInterval(Self.weekSeconds / 4)

        let timeline = curve.timeline(endingAt: Self.reset, over: start...Self.reset)

        // A quarter into the curve the median has used 12.5%; the band restarts from there.
        #expect(timeline.map(\.date) == [start, curveStart.addingTimeInterval(Self.weekSeconds / 2), Self.reset])
        #expect(timeline.map(\.medianUsedPercent) == [0, 12.5, 37.5])
        #expect(timeline.map(\.lowerUsedPercent) == [0, 8.75, 26.25])
        #expect(timeline.map(\.upperUsedPercent) == [0, 16.25, 48.75])
    }

    @Test
    func `timeline clips to a range that ends before the reset and is empty without overlap`() throws {
        let curve = try #require(TypicalWeekCurve(
            weeks: Self.pastWeeks(),
            windowMinutes: Self.weekMinutes,
            currentResetsAt: Self.reset))
        let start = Self.reset.addingTimeInterval(-Self.weekSeconds)
        let end = start.addingTimeInterval(Self.weekSeconds / 4)

        let clipped = curve.timeline(endingAt: Self.reset, over: start...end)
        #expect(clipped.map(\.date) == [start, end])
        #expect(clipped.map(\.medianUsedPercent) == [0, 12.5])

        let before = start.addingTimeInterval(-2 * Self.weekSeconds)
        #expect(curve.timeline(endingAt: Self.reset, over: before...start.addingTimeInterval(-60)).isEmpty)
    }

    @Test
    func `quantiles interpolate between ordered values`() {
        #expect(TypicalWeekCurve.quantile([10, 20, 30, 40], 0.5) == 25)
        #expect(TypicalWeekCurve.quantile([10, 20, 30, 40], 0.25) == 17.5)
        #expect(TypicalWeekCurve.quantile([7], 0.75) == 7)
        #expect(TypicalWeekCurve.quantile([], 0.5) == 0)
    }

    // MARK: - Fixtures

    private static let weekMinutes = 10080
    private static let weekSeconds = TimeInterval(10080 * 60)
    private static let reset = Date(timeIntervalSince1970: 1_780_000_000)

    /// Four finished weeks using 20, 40, 60 and 80 percent, linearly on a three-point grid.
    private static func pastWeeks() -> [TypicalWeekCurve.Week] {
        [20.0, 40, 60, 80].enumerated().map { index, end in
            TypicalWeekCurve.Week(
                resetsAt: self.reset.addingTimeInterval(-Double(index + 1) * self.weekSeconds),
                windowMinutes: self.weekMinutes,
                usedPercent: [0, end / 2, end])
        }
    }
}
