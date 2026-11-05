import CodexBarCore
import Foundation

struct QuotaBurndownModel: Equatable, Sendable {
    private static let resetEquivalenceTolerance: TimeInterval = 2 * 60

    struct Sample: Equatable, Sendable {
        let date: Date
        let remainingPercent: Double
    }

    /// A point of the learned typical week, as remaining quota.
    struct TypicalSample: Equatable, Sendable {
        let date: Date
        /// Remaining after a heavier week (the upper quartile of past usage).
        let lowRemainingPercent: Double
        let medianRemainingPercent: Double
        /// Remaining after a lighter week (the lower quartile of past usage).
        let highRemainingPercent: Double
    }

    let start: Date
    let reset: Date
    let now: Date
    let samples: [Sample]
    /// Expected remaining quota, from the same work-day weighting as the pace text.
    let ideal: [Sample]
    /// The current burn rate projected from `now` to the run-out or the reset, whichever comes first.
    let projection: [Sample]
    /// Set only when the projection empties the quota before the reset.
    let runOut: Date?
    /// The learned typical week on this window's time axis; empty without a curve or when it misses the window.
    let typicalWeek: [TypicalSample]

    init?(
        history: PlanUtilizationSeriesHistory,
        window: RateWindow,
        now: Date,
        workDays: Int? = nil,
        calendar: Calendar = .current,
        typicalWeek: TypicalWeekCurve? = nil)
    {
        guard window.usedPercent.isFinite,
              !window.isSyntheticPlaceholder,
              let windowMinutes = window.windowMinutes,
              windowMinutes > 0,
              let reset = window.resetsAt,
              reset.timeIntervalSinceReferenceDate.isFinite,
              now.timeIntervalSinceReferenceDate.isFinite
        else { return nil }

        let duration = Double(windowMinutes) * 60
        guard duration.isFinite, duration > 0 else { return nil }

        let start = reset.addingTimeInterval(-duration)
        guard start.timeIntervalSinceReferenceDate.isFinite,
              start <= now,
              now < reset
        else { return nil }

        let historicalSamples = history.entries.compactMap { entry -> (Date, Double)? in
            guard entry.capturedAt >= start,
                  entry.capturedAt <= now,
                  entry.capturedAt.timeIntervalSinceReferenceDate.isFinite,
                  entry.usedPercent.isFinite,
                  entry.resetsAt.map({
                      abs($0.timeIntervalSince(reset)) <= Self.resetEquivalenceTolerance
                  }) ?? true
            else { return nil }
            return (entry.capturedAt, entry.usedPercent)
        }

        var currentSegment: [(Date, Double)] = []
        for sample in historicalSamples + [(now, window.usedPercent)] {
            if let last = currentSegment.last {
                if sample.0 == last.0 {
                    currentSegment[currentSegment.count - 1] = sample
                    continue
                }
                if sample.1 < last.1 {
                    currentSegment.removeAll(keepingCapacity: true)
                }
            }
            currentSegment.append(sample)
        }

        self.start = start
        self.reset = reset
        self.now = now
        self.samples = currentSegment.map { date, usedPercent in
            Sample(
                date: date,
                remainingPercent: (100 - usedPercent).clamped(to: 0...100))
        }
        self.ideal = UsagePace.expectedCurve(
            windowStart: start,
            resetsAt: reset,
            workDays: workDays,
            calendar: calendar).map(Self.remainingSample)
        let projection = UsagePace.projection(
            window: window,
            now: now,
            workDays: workDays,
            calendar: calendar)
        self.projection = projection?.points.map(Self.remainingSample) ?? []
        self.runOut = projection?.runOutAt
        self.typicalWeek = typicalWeek?.timeline(endingAt: reset, over: start...reset).map(Self.typicalSample) ?? []
    }

    private static func remainingSample(_ point: UsagePace.CurvePoint) -> Sample {
        Sample(date: point.date, remainingPercent: (100 - point.usedPercent).clamped(to: 0...100))
    }

    private static func typicalSample(_ point: TypicalWeekCurve.TimedPoint) -> TypicalSample {
        TypicalSample(
            date: point.date,
            lowRemainingPercent: (100 - point.upperUsedPercent).clamped(to: 0...100),
            medianRemainingPercent: (100 - point.medianUsedPercent).clamped(to: 0...100),
            highRemainingPercent: (100 - point.lowerUsedPercent).clamped(to: 0...100))
    }
}
