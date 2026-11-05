import Foundation

/// Groups raw quota captures into plan-fit windows for surfaces that cannot reuse the plan usage chart's bars,
/// such as the compact chart on a menu card.
///
/// Windows sit on the same reset lattice the plan usage chart uses: the latest observed reset anchors it, a
/// capture with a reset snaps to the nearest lattice boundary, and a capture without one belongs to the window
/// whose boundary follows it. Without any observed reset, windows are fixed buckets of the window length.
extension PlanFit {
    public struct HistoryEntry: Equatable, Sendable {
        public let capturedAt: Date
        public let usedPercent: Double
        public let resetsAt: Date?

        public init(capturedAt: Date, usedPercent: Double, resetsAt: Date?) {
            self.capturedAt = capturedAt
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    public struct WindowGrouping: Equatable, Sendable {
        /// Windows with at least one capture, oldest first, within the last `maxWindows` periods.
        public let windows: [WindowInput]
        /// The boundary (reset) of the window that contains the reference time.
        public let currentResetsAt: Date
        public let windowMinutes: Int

        /// Whole periods from `resetsAt` back from the current window: 0 for the current window.
        public func periodsBeforeCurrent(_ resetsAt: Date) -> Int {
            let interval = Double(self.windowMinutes) * 60
            guard interval > 0 else { return 0 }
            return Int((self.currentResetsAt.timeIntervalSince(resetsAt) / interval).rounded())
        }
    }

    /// Nil without a positive window length, a positive window budget or any finite capture.
    public static func windowGrouping(
        entries: [HistoryEntry],
        windowMinutes: Int,
        now: Date,
        maxWindows: Int) -> WindowGrouping?
    {
        guard windowMinutes > 0, maxWindows > 0 else { return nil }
        let finite = entries.filter { $0.usedPercent.isFinite && $0.capturedAt.timeIntervalSince1970.isFinite }
        guard !finite.isEmpty else { return nil }
        let interval = Double(windowMinutes) * 60
        let reference = finite.compactMap(\.resetsAt).map(Self.wholeSecond).max()
        let current = Self.boundary(containing: now, reference: reference, interval: interval)

        var capturesByBoundary: [Date: [Capture]] = [:]
        for entry in finite {
            let boundary: Date = if let resetsAt = entry.resetsAt.map(Self.wholeSecond) {
                reference.map { Self.closestBoundary(to: resetsAt, reference: $0, interval: interval) } ?? resetsAt
            } else {
                Self.boundary(containing: entry.capturedAt, reference: reference, interval: interval)
            }
            let periods = Int((current.timeIntervalSince(boundary) / interval).rounded())
            guard periods >= 0, periods < maxWindows else { continue }
            capturesByBoundary[boundary, default: []].append(Capture(
                capturedAt: entry.capturedAt,
                usedPercent: entry.usedPercent.clamped(to: 0...100)))
        }
        let windows = capturesByBoundary.keys.sorted().map { boundary in
            WindowInput(resetsAt: boundary, captures: capturesByBoundary[boundary] ?? [])
        }
        return WindowGrouping(windows: windows, currentResetsAt: current, windowMinutes: windowMinutes)
    }

    private static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }

    private static func closestBoundary(to date: Date, reference: Date, interval: TimeInterval) -> Date {
        let periods = (date.timeIntervalSince(reference) / interval).rounded()
        return reference.addingTimeInterval(periods * interval)
    }

    /// The first lattice boundary at or after `date`; fixed buckets of `interval` without a reference.
    private static func boundary(containing date: Date, reference: Date?, interval: TimeInterval) -> Date {
        if let reference {
            let periods = ceil(date.timeIntervalSince(reference) / interval)
            return reference.addingTimeInterval(periods * interval)
        }
        let bucket = floor(date.timeIntervalSince1970 / interval)
        return Date(timeIntervalSince1970: (bucket + 1) * interval)
    }
}
