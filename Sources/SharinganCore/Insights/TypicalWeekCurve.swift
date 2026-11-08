import Foundation

/// A typical quota window learned from past windows: the median cumulative usage and the middle half
/// (lower to upper quartile) of past windows, at each point of an even grid from window start to reset.
///
/// Past windows are cumulative used-percent curves sampled on the same grid. Only windows of the requested
/// length that reset at least half a window before the current reset count, so the window in progress never
/// describes itself.
public struct TypicalWeekCurve: Equatable, Sendable {
    public struct Week: Equatable, Sendable {
        public let resetsAt: Date
        public let windowMinutes: Int
        /// Cumulative used percent on an even grid from the window start (first value) to the reset (last value).
        public let usedPercent: [Double]

        public init(resetsAt: Date, windowMinutes: Int, usedPercent: [Double]) {
            self.resetsAt = resetsAt
            self.windowMinutes = windowMinutes
            self.usedPercent = usedPercent
        }
    }

    public struct Point: Equatable, Sendable {
        /// Position in the window: 0 at the start, 1 at the reset.
        public let fraction: Double
        public let lowerUsedPercent: Double
        public let medianUsedPercent: Double
        public let upperUsedPercent: Double
    }

    public struct TimedPoint: Equatable, Sendable {
        public let date: Date
        public let lowerUsedPercent: Double
        public let medianUsedPercent: Double
        public let upperUsedPercent: Double
    }

    public static let defaultMinimumWeeks = 3
    static let lowerQuantile = 0.25
    static let upperQuantile = 0.75
    /// Grid points closer than this to a timeline boundary are dropped in favor of the boundary itself.
    private static let boundaryTolerance: TimeInterval = 1

    public let windowMinutes: Int
    public let weekCount: Int
    public let points: [Point]

    public var windowDuration: TimeInterval {
        TimeInterval(self.windowMinutes) * 60
    }

    public init?(
        weeks: [Week],
        windowMinutes: Int,
        currentResetsAt: Date,
        minimumWeeks: Int = TypicalWeekCurve.defaultMinimumWeeks)
    {
        guard windowMinutes > 0, currentResetsAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let latestEligibleReset = currentResetsAt.addingTimeInterval(-TimeInterval(windowMinutes) * 60 / 2)

        // The newest eligible window sets the grid; windows sampled on another grid are skipped.
        var sharedGridCount: Int?
        var curves: [[Double]] = []
        for week in weeks.sorted(by: { $0.resetsAt > $1.resetsAt }) {
            guard week.windowMinutes == windowMinutes,
                  week.resetsAt <= latestEligibleReset,
                  week.usedPercent.count >= 2,
                  week.usedPercent.allSatisfy(\.isFinite)
            else { continue }
            if let sharedGridCount, week.usedPercent.count != sharedGridCount { continue }
            sharedGridCount = week.usedPercent.count
            curves.append(week.usedPercent.map { min(100, max(0, $0)) })
        }
        guard let gridCount = sharedGridCount, curves.count >= max(1, minimumWeeks) else { return nil }

        let denominator = Double(gridCount - 1)
        var points: [Point] = []
        points.reserveCapacity(gridCount)
        var lower = 0.0
        var median = 0.0
        var upper = 0.0
        for index in 0..<gridCount {
            let values = curves.map { $0[index] }.sorted()
            // Cumulative usage never decreases, so neither may the typical curve.
            lower = max(lower, Self.quantile(values, Self.lowerQuantile))
            median = max(median, Self.quantile(values, 0.5))
            upper = max(upper, Self.quantile(values, Self.upperQuantile))
            points.append(Point(
                fraction: Double(index) / denominator,
                lowerUsedPercent: lower,
                medianUsedPercent: max(lower, median),
                upperUsedPercent: max(lower, median, upper)))
        }

        self.windowMinutes = windowMinutes
        self.weekCount = curves.count
        self.points = points
    }

    /// The curve on a time axis for a window that resets at `reset`, clipped to `range`.
    ///
    /// The curve spans `windowDuration` and ends at `reset`. When `range` starts after the curve does (the
    /// window started mid-curve), the first point sits at the range start and every value is rebased to zero
    /// there, so the typical line starts where the window's own usage does. Returns the range start, every grid
    /// point strictly inside the visible span, and the visible end; empty when nothing overlaps.
    public func timeline(endingAt reset: Date, over range: ClosedRange<Date>) -> [TimedPoint] {
        let duration = self.windowDuration
        guard duration > 0, self.points.count >= 2 else { return [] }
        let curveStart = reset.addingTimeInterval(-duration)
        let visibleStart = max(range.lowerBound, curveStart)
        let visibleEnd = min(range.upperBound, reset)
        guard visibleEnd > visibleStart else { return [] }

        var dates = [visibleStart]
        for point in self.points {
            let date = curveStart.addingTimeInterval(point.fraction * duration)
            if date.timeIntervalSince(visibleStart) > Self.boundaryTolerance,
               visibleEnd.timeIntervalSince(date) > Self.boundaryTolerance
            {
                dates.append(date)
            }
        }
        dates.append(visibleEnd)

        let base = self.value(atFraction: visibleStart.timeIntervalSince(curveStart) / duration)
        return dates.map { date in
            let value = self.value(atFraction: date.timeIntervalSince(curveStart) / duration)
            let lower = min(100, max(0, value.lowerUsedPercent - base.lowerUsedPercent))
            let median = min(100, max(0, value.medianUsedPercent - base.medianUsedPercent))
            let upper = min(100, max(0, value.upperUsedPercent - base.upperUsedPercent))
            // Rebasing each quantile on its own value can cross them; keep the band ordered.
            let low = min(lower, median, upper)
            let high = max(lower, median, upper)
            return TimedPoint(
                date: date,
                lowerUsedPercent: low,
                medianUsedPercent: min(high, max(low, median)),
                upperUsedPercent: high)
        }
    }

    /// Linear interpolation between grid points; `fraction` is clamped to the window.
    func value(atFraction fraction: Double) -> Point {
        let clamped = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let scaled = clamped * Double(self.points.count - 1)
        let lowerIndex = min(self.points.count - 1, max(0, Int(scaled.rounded(.down))))
        let upperIndex = min(self.points.count - 1, lowerIndex + 1)
        let lowerPoint = self.points[lowerIndex]
        let upperPoint = self.points[upperIndex]
        let ratio = upperIndex == lowerIndex ? 0 : scaled - Double(lowerIndex)
        return Point(
            fraction: clamped,
            lowerUsedPercent: Self.mix(lowerPoint.lowerUsedPercent, upperPoint.lowerUsedPercent, ratio),
            medianUsedPercent: Self.mix(lowerPoint.medianUsedPercent, upperPoint.medianUsedPercent, ratio),
            upperUsedPercent: Self.mix(lowerPoint.upperUsedPercent, upperPoint.upperUsedPercent, ratio))
    }

    private static func mix(_ lower: Double, _ upper: Double, _ ratio: Double) -> Double {
        lower + (upper - lower) * ratio
    }

    /// Linearly interpolated quantile of ascending `sorted` values.
    static func quantile(_ sorted: [Double], _ probability: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = min(1, max(0, probability)) * Double(sorted.count - 1)
        let lowerIndex = min(sorted.count - 1, Int(position.rounded(.down)))
        let upperIndex = min(sorted.count - 1, lowerIndex + 1)
        let ratio = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * ratio
    }
}
