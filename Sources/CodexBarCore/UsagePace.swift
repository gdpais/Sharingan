import Foundation

public struct UsagePace: Sendable {
    public enum Stage: Sendable {
        case onTrack
        case slightlyAhead
        case ahead
        case farAhead
        case slightlyBehind
        case behind
        case farBehind
    }

    public let stage: Stage
    public let deltaPercent: Double
    public let expectedUsedPercent: Double
    public let actualUsedPercent: Double
    public let etaSeconds: TimeInterval?
    public let willLastToReset: Bool
    public let runOutProbability: Double?
    public let speedMultiplierToReset: Double?

    public init(
        stage: Stage,
        deltaPercent: Double,
        expectedUsedPercent: Double,
        actualUsedPercent: Double,
        etaSeconds: TimeInterval?,
        willLastToReset: Bool,
        runOutProbability: Double? = nil,
        speedMultiplierToReset: Double? = nil)
    {
        self.stage = stage
        self.deltaPercent = deltaPercent
        self.expectedUsedPercent = expectedUsedPercent
        self.actualUsedPercent = actualUsedPercent
        self.etaSeconds = etaSeconds
        self.willLastToReset = willLastToReset
        self.runOutProbability = runOutProbability
        self.speedMultiplierToReset = speedMultiplierToReset
    }

    package static func dailyTarget(
        remaining: Double,
        resetsAt: Date?,
        now: Date,
        calendar: Calendar = .current) -> Double?
    {
        guard remaining.isFinite, remaining >= 0,
              let resetsAt, resetsAt.timeIntervalSince1970.isFinite, resetsAt > now,
              let resetDay = calendar.dateInterval(of: .day, for: resetsAt),
              let days = calendar.dateComponents(
                  [.day], from: calendar.startOfDay(for: now), to: resetDay.start).day
        else { return nil }
        // Today counts even when almost over. A midnight reset starts the next allowance.
        let dayCount = max(1, days + (resetsAt > resetDay.start ? 1 : 0))
        return remaining / Double(dayCount)
    }

    public static func weekly(
        window: RateWindow,
        now: Date = .init(),
        defaultWindowMinutes: Int = 10080,
        workDays: Int? = nil,
        calendar: Calendar = .current) -> UsagePace?
    {
        guard let timing = Self.paceTiming(
            window: window,
            now: now,
            defaultWindowMinutes: defaultWindowMinutes,
            workDays: workDays,
            calendar: calendar)
        else { return nil }
        let resetsAt = timing.resetsAt
        let elapsed = timing.elapsed
        let workdayProgress = timing.workdayProgress
        let expected = timing.expectedUsedPercent
        let actual = window.usedPercent.clamped(to: 0...100)
        if elapsed == 0, actual > 0 {
            return nil
        }
        let delta = actual - expected
        let stage = Self.stage(for: delta)

        var etaSeconds: TimeInterval?
        var willLastToReset = false

        let paceElapsed = timing.paceElapsed
        let effectiveTimeUntilReset = timing.effectiveTimeUntilReset
        let projectedRemainingUsage = paceElapsed > 0
            ? actual * effectiveTimeUntilReset / paceElapsed
            : 0
        let speedMultiplierToReset = Self.safeSpeedMultiplier(
            remainingCapacity: 100 - actual,
            projectedRemainingUsage: projectedRemainingUsage)
        if actual >= 100 {
            etaSeconds = 0
        } else if paceElapsed > 0, actual > 0 {
            let rate = actual / paceElapsed
            if rate > 0 {
                let remaining = 100 - actual
                let candidate = remaining / rate
                if candidate >= effectiveTimeUntilReset {
                    willLastToReset = true
                } else if let workDays = workdayProgress?.workDays {
                    etaSeconds = Self.wallClockInterval(
                        from: now,
                        to: resetsAt,
                        consumingWorkSeconds: candidate,
                        workDays: workDays,
                        calendar: calendar)
                } else {
                    etaSeconds = candidate
                }
            }
        } else if paceElapsed > 0, actual == 0 {
            willLastToReset = true
        }

        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: nil,
            speedMultiplierToReset: speedMultiplierToReset)
    }

    public static func historical(
        expectedUsedPercent: Double,
        actualUsedPercent: Double,
        etaSeconds: TimeInterval?,
        willLastToReset: Bool,
        runOutProbability: Double?,
        projectedRemainingUsage: Double? = nil) -> UsagePace
    {
        let expected = expectedUsedPercent.clamped(to: 0...100)
        let actual = actualUsedPercent.clamped(to: 0...100)
        let delta = actual - expected
        return UsagePace(
            stage: Self.stage(for: delta),
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: runOutProbability,
            speedMultiplierToReset: projectedRemainingUsage.flatMap {
                Self.safeSpeedMultiplier(
                    remainingCapacity: 100 - actual,
                    projectedRemainingUsage: $0)
            })
    }

    private static func safeSpeedMultiplier(
        remainingCapacity: Double,
        projectedRemainingUsage: Double) -> Double?
    {
        guard remainingCapacity > 0, projectedRemainingUsage > 0 else { return nil }
        let multiplier = remainingCapacity / projectedRemainingUsage
        return multiplier.isFinite ? multiplier : nil
    }

    // MARK: - Expected curve and projection

    /// The share of a window's quota used by `date`.
    public struct CurvePoint: Sendable, Equatable {
        public let date: Date
        public let usedPercent: Double

        public init(date: Date, usedPercent: Double) {
            self.date = date
            self.usedPercent = usedPercent
        }
    }

    public struct Projection: Sendable, Equatable {
        /// Projected usage from `now` until the run-out or the reset, whichever comes first.
        public let points: [CurvePoint]
        /// Set only when projected usage reaches 100% before the reset.
        public let runOutAt: Date?

        public init(points: [CurvePoint], runOutAt: Date?) {
            self.points = points
            self.runOutAt = runOutAt
        }
    }

    /// Expected usage across a window with the same work-day weighting as `weekly(...)`.
    /// Points sit at local day boundaries: the curve rises linearly on work days and stays flat on other days.
    /// Only 7-day windows use `workDays`; other windows get the linear `[0, 100]` curve.
    public static func expectedCurve(
        windowStart: Date,
        resetsAt: Date,
        workDays: Int? = nil,
        calendar: Calendar = .current) -> [CurvePoint]
    {
        let duration = resetsAt.timeIntervalSince(windowStart)
        guard duration.isFinite, duration > 0 else { return [] }
        let linear = [
            CurvePoint(date: windowStart, usedPercent: 0),
            CurvePoint(date: resetsAt, usedPercent: 100),
        ]
        guard let workDays = Self.effectiveWorkDays(workDays, duration: duration),
              let slices = Self.daySlices(from: windowStart, to: resetsAt, workDays: workDays, calendar: calendar)
        else { return linear }
        let totalWorkSeconds = slices.reduce(TimeInterval(0)) { $1.isWorkday ? $0 + $1.duration : $0 }
        guard totalWorkSeconds > 0 else { return linear }

        var points = [CurvePoint(date: windowStart, usedPercent: 0)]
        var elapsedWorkSeconds: TimeInterval = 0
        for slice in slices {
            if slice.isWorkday {
                elapsedWorkSeconds += slice.duration
            }
            points.append(CurvePoint(
                date: slice.end,
                usedPercent: ((elapsedWorkSeconds / totalWorkSeconds) * 100).clamped(to: 0...100)))
        }
        return points
    }

    /// Projects the current burn rate forward with the same rate, ETA and work-day weighting as `weekly(...)`.
    public static func projection(
        window: RateWindow,
        now: Date = .init(),
        defaultWindowMinutes: Int = 10080,
        workDays: Int? = nil,
        calendar: Calendar = .current) -> Projection?
    {
        guard let pace = Self.weekly(
            window: window,
            now: now,
            defaultWindowMinutes: defaultWindowMinutes,
            workDays: workDays,
            calendar: calendar)
        else { return nil }
        guard let timing = Self.paceTiming(
            window: window,
            now: now,
            defaultWindowMinutes: defaultWindowMinutes,
            workDays: workDays,
            calendar: calendar)
        else { return nil }

        let actual = pace.actualUsedPercent
        if actual >= 100 {
            return Projection(points: [CurvePoint(date: now, usedPercent: 100)], runOutAt: now)
        }
        guard timing.paceElapsed > 0 else { return nil }
        let rate = actual / timing.paceElapsed
        var runOutAt: Date?
        if !pace.willLastToReset, let etaSeconds = pace.etaSeconds {
            let candidate = now.addingTimeInterval(etaSeconds)
            if candidate > now, candidate < timing.resetsAt {
                runOutAt = candidate
            }
        }
        let end = runOutAt ?? timing.resetsAt

        var points = [CurvePoint(date: now, usedPercent: actual)]
        if let workDays = timing.workdayProgress?.workDays,
           let slices = Self.daySlices(from: now, to: end, workDays: workDays, calendar: calendar)
        {
            var used = actual
            for slice in slices {
                if slice.isWorkday {
                    used += rate * slice.duration
                }
                points.append(CurvePoint(date: slice.end, usedPercent: min(used, 100)))
            }
        } else {
            points.append(CurvePoint(
                date: end,
                usedPercent: min(actual + rate * end.timeIntervalSince(now), 100)))
        }
        if runOutAt != nil, points.count > 1 {
            points[points.count - 1] = CurvePoint(date: end, usedPercent: 100)
        }
        return Projection(points: points, runOutAt: runOutAt)
    }

    // MARK: - Shared pace timing

    private static let weeklyWindowSeconds: TimeInterval = 10080 * 60

    private struct PaceTiming {
        let resetsAt: Date
        let duration: TimeInterval
        let elapsed: TimeInterval
        let timeUntilReset: TimeInterval
        let workdayProgress: WorkdayProgress?

        var paceElapsed: TimeInterval {
            self.workdayProgress?.elapsedSeconds ?? self.elapsed
        }

        var effectiveTimeUntilReset: TimeInterval {
            self.workdayProgress?.remainingSeconds ?? self.timeUntilReset
        }

        var expectedUsedPercent: Double {
            self.workdayProgress?.expectedUsedPercent
                ?? ((self.elapsed / self.duration) * 100).clamped(to: 0...100)
        }
    }

    private static func paceTiming(
        window: RateWindow,
        now: Date,
        defaultWindowMinutes: Int,
        workDays: Int?,
        calendar: Calendar) -> PaceTiming?
    {
        guard let resetsAt = window.resetsAt else { return nil }
        let minutes = window.windowMinutes ?? defaultWindowMinutes
        guard minutes > 0 else { return nil }

        let duration = TimeInterval(minutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0 else { return nil }
        guard timeUntilReset <= duration else { return nil }
        let elapsed = (duration - timeUntilReset).clamped(to: 0...duration)
        let workdayProgress = Self.effectiveWorkDays(workDays, duration: duration).flatMap {
            Self.workdayProgress(
                now: now,
                duration: duration,
                resetsAt: resetsAt,
                workDays: $0,
                calendar: calendar)
        }
        return PaceTiming(
            resetsAt: resetsAt,
            duration: duration,
            elapsed: elapsed,
            timeUntilReset: timeUntilReset,
            workdayProgress: workdayProgress)
    }

    /// Work days only apply to 7-day windows and to 2...6 work days; anything else paces linearly.
    private static func effectiveWorkDays(_ workDays: Int?, duration: TimeInterval) -> Int? {
        guard let workDays, workDays >= 2, workDays < 7,
              abs(duration - Self.weeklyWindowSeconds) < 0.5
        else { return nil }
        return workDays
    }

    private struct WorkdayProgress {
        let workDays: Int
        let totalSeconds: TimeInterval
        let elapsedSeconds: TimeInterval
        let remainingSeconds: TimeInterval

        var expectedUsedPercent: Double {
            ((self.elapsedSeconds / self.totalSeconds) * 100).clamped(to: 0...100)
        }
    }

    private struct DaySlice {
        let start: Date
        let end: Date
        let isWorkday: Bool

        var duration: TimeInterval {
            self.end.timeIntervalSince(self.start)
        }
    }

    /// Splits `start..<end` at local day boundaries so reset offsets do not shift weekday classification.
    private static func daySlices(
        from start: Date,
        to end: Date,
        workDays: Int,
        calendar: Calendar) -> [DaySlice]?
    {
        var slices: [DaySlice] = []
        var cursor = start
        while cursor < end {
            guard let startOfNextDay = Self.nextDayBoundary(after: cursor, calendar: calendar),
                  startOfNextDay > cursor
            else {
                return nil
            }
            let sliceEnd = min(startOfNextDay, end)
            slices.append(DaySlice(
                start: cursor,
                end: sliceEnd,
                isWorkday: Self.isWorkday(cursor, calendar: calendar, workDays: workDays)))
            cursor = sliceEnd
        }
        return slices
    }

    private static func workdayProgress(
        now: Date,
        duration: TimeInterval,
        resetsAt: Date,
        workDays: Int,
        calendar: Calendar) -> WorkdayProgress?
    {
        let windowStart = resetsAt.addingTimeInterval(-duration)
        guard let slices = Self.daySlices(from: windowStart, to: resetsAt, workDays: workDays, calendar: calendar)
        else { return nil }

        var totalWorkSeconds: TimeInterval = 0
        var elapsedWorkSeconds: TimeInterval = 0
        var remainingWorkSeconds: TimeInterval = 0
        for slice in slices where slice.isWorkday {
            totalWorkSeconds += slice.duration
            if now > slice.start {
                elapsedWorkSeconds += min(now, slice.end).timeIntervalSince(slice.start)
            }
            if now < slice.end {
                remainingWorkSeconds += slice.end.timeIntervalSince(max(now, slice.start))
            }
        }

        guard totalWorkSeconds > 0 else { return nil }
        return WorkdayProgress(
            workDays: workDays,
            totalSeconds: totalWorkSeconds,
            elapsedSeconds: elapsedWorkSeconds,
            remainingSeconds: remainingWorkSeconds)
    }

    private static func wallClockInterval(
        from now: Date,
        to resetsAt: Date,
        consumingWorkSeconds requiredWorkSeconds: TimeInterval,
        workDays: Int,
        calendar: Calendar) -> TimeInterval?
    {
        guard requiredWorkSeconds > 0 else { return 0 }
        guard let slices = Self.daySlices(from: now, to: resetsAt, workDays: workDays, calendar: calendar)
        else { return nil }

        var remaining = requiredWorkSeconds
        for slice in slices where slice.isWorkday {
            if remaining <= slice.duration {
                return slice.start.addingTimeInterval(remaining).timeIntervalSince(now)
            }
            remaining -= slice.duration
        }
        return nil
    }

    private static func nextDayBoundary(after date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    private static func isWorkday(_ date: Date, calendar: Calendar, workDays: Int) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return isoWeekday <= workDays
    }

    private static func stage(for delta: Double) -> Stage {
        let absDelta = abs(delta)
        if absDelta <= 2 { return .onTrack }
        if absDelta <= 6 { return delta >= 0 ? .slightlyAhead : .slightlyBehind }
        if absDelta <= 12 { return delta >= 0 ? .ahead : .behind }
        return delta >= 0 ? .farAhead : .farBehind
    }
}
