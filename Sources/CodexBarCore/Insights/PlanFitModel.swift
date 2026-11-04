import Foundation

/// Plan fit: how full each quota window got, how often it hit the cap, and a plain-rule verdict.
///
/// The caller groups captures into windows (the plan utilization chart already does this for its bars), and
/// this type only summarizes them, so every surface shares one definition. The verdict is a fixed rule over
/// the median peak and the capped share, never a model.
public enum PlanFit {
    // MARK: - Rules

    /// A capture at or above this used percent means the window hit its cap.
    public static let cappedPercent: Double = 100
    /// A median peak below this means most windows leave much of the plan unused.
    public static let underusedMedianPercent: Double = 35
    /// Capping in at least this share of windows (one in four) means the cap gets in the way.
    public static let cappedOftenShare: Double = 0.25
    /// Fewer settled windows than this are too few for a verdict.
    public static let minimumWindowsForVerdict = 4
    /// Windows this long or shorter are sessions; their capped count is reported per week.
    public static let sessionWindowMaxMinutes = 300

    private static let secondsPerWeek: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Types

    public enum Cadence: String, Sendable {
        case session
        case weekly
        case monthly
        case other

        public init(windowMinutes: Int) {
            if windowMinutes > 0, windowMinutes <= PlanFit.sessionWindowMaxMinutes {
                self = .session
            } else if (10070...10090).contains(windowMinutes) {
                self = .weekly
            } else if (40320...44640).contains(windowMinutes) {
                // 28 to 31 days, which includes the 30-day monthly sentinel.
                self = .monthly
            } else {
                self = .other
            }
        }
    }

    public struct Capture: Equatable, Sendable {
        public let capturedAt: Date
        public let usedPercent: Double

        public init(capturedAt: Date, usedPercent: Double) {
            self.capturedAt = capturedAt
            self.usedPercent = usedPercent
        }
    }

    public struct WindowInput: Equatable, Sendable {
        /// When the window resets, which is also when it ends.
        public let resetsAt: Date
        public let captures: [Capture]

        public init(resetsAt: Date, captures: [Capture]) {
            self.resetsAt = resetsAt
            self.captures = captures
        }
    }

    public struct Window: Equatable, Sendable {
        public let resetsAt: Date
        /// Highest captured used percent, clamped to 0...100; zero without captures.
        public let peakPercent: Double
        /// The first capture at or above `PlanFit.cappedPercent`, or nil when the window never capped.
        public let firstCappedAt: Date?
        /// Hours from the first capped capture to the reset, at most the window length; zero when not capped.
        public let cappedHours: Double
        /// The window had not reset yet at the reference time.
        public let isCurrent: Bool
        public let captureCount: Int

        public var isCapped: Bool {
            self.firstCappedAt != nil
        }

        /// A window counts toward the summary once its outcome is known: it has reset, or it already capped.
        public var isSettled: Bool {
            self.captureCount > 0 && (!self.isCurrent || self.isCapped)
        }
    }

    public enum Verdict: String, Sendable {
        case notEnoughHistory
        case underused
        case hitsCapOften
        case fits
    }

    public struct Summary: Equatable, Sendable {
        public let cadence: Cadence
        /// One entry per input window, in input order.
        public let windows: [Window]
        public let settledWindowCount: Int
        public let cappedWindowCount: Int
        /// Median peak of the settled windows; nil when none are settled.
        public let medianPeakPercent: Double?
        /// Hours capped across the settled windows.
        public let cappedHours: Double
        /// Capped sessions per week of settled history, counting at least one week; nil unless sessions.
        public let cappedSessionsPerWeek: Double?
        public let verdict: Verdict
    }

    // MARK: - Summary

    public static func summary(windows inputs: [WindowInput], windowMinutes: Int, now: Date) -> Summary {
        let windows = inputs.map { self.window($0, windowMinutes: windowMinutes, now: now) }
        let settled = windows.filter(\.isSettled)
        let cappedCount = settled.filter(\.isCapped).count
        let medianPeak = self.median(settled.map(\.peakPercent))
        let cadence = Cadence(windowMinutes: windowMinutes)
        let perWeek: Double? = cadence == .session
            ? self.cappedPerWeek(settled, cappedCount: cappedCount, windowMinutes: windowMinutes)
            : nil
        return Summary(
            cadence: cadence,
            windows: windows,
            settledWindowCount: settled.count,
            cappedWindowCount: cappedCount,
            medianPeakPercent: medianPeak,
            cappedHours: settled.reduce(0) { $0 + $1.cappedHours },
            cappedSessionsPerWeek: perWeek,
            verdict: self.verdict(
                medianPeakPercent: medianPeak,
                cappedWindowCount: cappedCount,
                windowCount: settled.count))
    }

    /// Peak, capped flag and hours capped for one window. Captures may arrive in any order and at any spacing.
    public static func window(_ input: WindowInput, windowMinutes: Int, now: Date) -> Window {
        let captures = input.captures
            .filter(\.usedPercent.isFinite)
            .sorted { $0.capturedAt < $1.capturedAt }
        let peak = captures.map(\.usedPercent).max().map { $0.clamped(to: 0...100) } ?? 0
        let firstCappedAt = captures.first(where: { $0.usedPercent >= self.cappedPercent })?.capturedAt
        var cappedSeconds: TimeInterval = 0
        if let firstCappedAt {
            cappedSeconds = max(0, input.resetsAt.timeIntervalSince(firstCappedAt))
            if windowMinutes > 0 {
                cappedSeconds = min(cappedSeconds, Double(windowMinutes) * 60)
            }
        }
        return Window(
            resetsAt: input.resetsAt,
            peakPercent: peak,
            firstCappedAt: firstCappedAt,
            cappedHours: cappedSeconds / 3600,
            isCurrent: input.resetsAt > now,
            captureCount: captures.count)
    }

    /// The middle value, or the mean of the two middle values for an even count; nil when empty.
    public static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Capping often wins over a low median: a plan that runs out one window in four does not have spare room.
    public static func verdict(medianPeakPercent: Double?, cappedWindowCount: Int, windowCount: Int) -> Verdict {
        guard windowCount >= self.minimumWindowsForVerdict, let medianPeakPercent else { return .notEnoughHistory }
        if Double(cappedWindowCount) >= Double(windowCount) * self.cappedOftenShare {
            return .hitsCapOften
        }
        if medianPeakPercent < self.underusedMedianPercent {
            return .underused
        }
        return .fits
    }

    private static func cappedPerWeek(_ settled: [Window], cappedCount: Int, windowMinutes: Int) -> Double? {
        let resets = settled.map(\.resetsAt)
        guard let earliest = resets.min(), let latest = resets.max() else { return nil }
        // The span runs from the start of the earliest window to the end of the latest one. Short histories
        // count as a full week so a single busy day does not extrapolate into a weekly rate.
        let span = latest.timeIntervalSince(earliest) + Double(max(windowMinutes, 0)) * 60
        let weeks = max(1, span / self.secondsPerWeek)
        return Double(cappedCount) / weeks
    }
}
