import Foundation

/// Pure math behind the cost history chart: which models get their own stacked series, how a
/// day's bar splits into those series plus "Other", where weekends fall, and the change against
/// the previous period of equal length.
///
/// It knows nothing about colors or views, so the menu, the CLI and a future server can share it.
public enum CostHistoryModelStack {
    public enum Metric: Sendable, Equatable {
        case cost
        case tokens
    }

    /// One stacked series: a top model by rank (0 is the largest), or everything else folded together.
    public enum Series: Hashable, Sendable {
        case model(Int)
        case other
    }

    /// One slice of a day's bar, in the metric's units.
    public struct Segment: Equatable, Sendable {
        public let series: Series
        public let start: Double
        public let end: Double

        public init(series: Series, start: Double, end: Double) {
            self.series = series
            self.start = start
            self.end = end
        }
    }

    /// The stacked models of a range and each day's segments, keyed by the entry's day key.
    public struct Stack: Equatable, Sendable {
        /// Trimmed model names that get their own series, by rank.
        public let models: [String]
        /// Bottom-to-top segments for each stacked day.
        public let segmentsByDayKey: [String: [Segment]]

        public init(models: [String], segmentsByDayKey: [String: [Segment]]) {
            self.models = models
            self.segmentsByDayKey = segmentsByDayKey
        }

        /// Whether any day folds part of its bar into "Other".
        public var hasOther: Bool {
            self.segmentsByDayKey.values.contains { segments in
                segments.contains { $0.series == .other }
            }
        }
    }

    /// Models that get their own stacked series; the rest fold into "Other".
    public static let maxStackedModels = 2
    /// Ranges longer than this get no weekend shading: each weekend would be a sliver.
    public static let maxWeekendShadingDays = 92
    /// Shorter windows compare a partial today against whole days, so no delta is reported.
    public static let minimumDeltaDays = 7
    /// "Other" remainders below this share of a bar are rounding noise between the per-model
    /// figures and the day total, not a real series.
    static let otherTolerance = 0.001

    // MARK: - Stacking

    /// Per-model totals over `entries`, keyed by trimmed model name. Missing, negative and
    /// non-finite values count as zero; blank names are skipped.
    public static func modelTotals(
        _ entries: [CostUsageDailyReport.Entry],
        metric: Metric) -> [String: Double]
    {
        var totals: [String: Double] = [:]
        for entry in entries {
            for item in entry.modelBreakdowns ?? [] {
                let name = self.seriesName(item.modelName)
                guard !name.isEmpty else { continue }
                totals[name, default: 0] += self.value(of: item, metric: metric) ?? 0
            }
        }
        return totals
    }

    /// The models that get their own series: positive totals only, ordered by total descending and
    /// then name ascending, so the same data always yields the same order and palette slots.
    public static func topModels(
        _ entries: [CostUsageDailyReport.Entry],
        metric: Metric,
        limit: Int = CostHistoryModelStack.maxStackedModels) -> [String]
    {
        let ranked = self.modelTotals(entries, metric: metric)
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
        return Array(ranked.prefix(max(0, limit)))
    }

    /// Splits one day's bar of height `total` into segments, bottom to top: each top model in rank
    /// order, then "Other" for the rest. Segments are clamped to the bar, so they always end at
    /// `total` even when the per-model figures overshoot it, and any unattributed remainder folds
    /// into "Other". Empty when the day has no model breakdown, so the caller keeps its single bar.
    public static func segments(
        for entry: CostUsageDailyReport.Entry,
        total: Double,
        topModels: [String],
        metric: Metric) -> [Segment]
    {
        guard total.isFinite, total > 0, !topModels.isEmpty,
              let breakdowns = entry.modelBreakdowns, !breakdowns.isEmpty
        else { return [] }

        var byModel: [String: Double] = [:]
        for item in breakdowns {
            byModel[self.seriesName(item.modelName), default: 0] += self.value(of: item, metric: metric) ?? 0
        }

        var segments: [Segment] = []
        var cursor = 0.0
        for (rank, name) in topModels.enumerated() {
            let height = min(byModel[name] ?? 0, total - cursor)
            guard height > 0 else { continue }
            segments.append(Segment(series: .model(rank), start: cursor, end: cursor + height))
            cursor += height
        }
        if total - cursor > total * self.otherTolerance {
            segments.append(Segment(series: .other, start: cursor, end: total))
        } else if let last = segments.last {
            // Close the rounding gap so the stack ends exactly at the day's total.
            segments[segments.count - 1] = Segment(series: last.series, start: last.start, end: total)
        }
        return segments
    }

    /// Stacks each bar against the top models of the whole range, so hovering or selecting a day
    /// never reshuffles series. Nil when no model has a positive total or no day carries a
    /// breakdown, so the chart keeps its single-color bars.
    public static func stack(
        _ bars: [(entry: CostUsageDailyReport.Entry, total: Double)],
        metric: Metric) -> Stack?
    {
        let models = self.topModels(bars.map(\.entry), metric: metric)
        guard !models.isEmpty else { return nil }
        var segmentsByDayKey: [String: [Segment]] = [:]
        for bar in bars {
            let segments = self.segments(for: bar.entry, total: bar.total, topModels: models, metric: metric)
            if !segments.isEmpty {
                segmentsByDayKey[bar.entry.date] = segments
            }
        }
        guard !segmentsByDayKey.isEmpty else { return nil }
        return Stack(models: models, segmentsByDayKey: segmentsByDayKey)
    }

    // MARK: - Previous period

    /// Fractional change against the previous period of equal length (0.12 is +12%). Nil when either
    /// total is missing, negative or not finite, when the previous total is zero (growth from nothing
    /// has no percentage), or when the window is shorter than `minimumDeltaDays`.
    public static func periodDelta(currentTotal: Double?, previousPeriodTotal: Double?, days: Int) -> Double? {
        guard days >= self.minimumDeltaDays,
              let current = currentTotal,
              let previous = previousPeriodTotal,
              current.isFinite, previous.isFinite,
              current >= 0, previous > 0
        else { return nil }
        return (current - previous) / previous
    }

    /// The metric's total over the `days`-day window that ends the day before the rolling window
    /// ending on `now`'s local day starts. Nil when no entry in that window carries a value.
    ///
    /// `entries` must come from a scan that covered both windows; a shorter scan reads as no data.
    public static func previousPeriodTotal(
        _ entries: [CostUsageDailyReport.Entry],
        days: Int,
        now: Date,
        metric: Metric,
        calendar: Calendar = .current) -> Double?
    {
        guard days > 0, let previousEnd = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
        let window = CostReportingPeriod.rolling(days: days).entries(entries, now: previousEnd, calendar: calendar)
        let values = window.compactMap { self.value(of: $0, metric: metric) }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    // MARK: - Weekends

    /// Weekend days from `first` through `last` (inclusive local days), merged into runs of
    /// consecutive days. `calendar`'s own weekend definition applies, so it follows the user's
    /// region. Empty for ranges longer than `maxWeekendShadingDays`.
    public static func weekendIntervals(from first: Date, through last: Date, calendar: Calendar) -> [DateInterval] {
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        guard start <= end,
              let span = calendar.dateComponents([.day], from: start, to: end).day,
              span + 1 <= self.maxWeekendShadingDays
        else { return [] }

        var intervals: [DateInterval] = []
        var runStart: Date?
        var day = start
        for _ in 0...span {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            if calendar.isDateInWeekend(day) {
                if runStart == nil {
                    runStart = day
                }
            } else if let open = runStart {
                intervals.append(DateInterval(start: open, end: day))
                runStart = nil
            }
            day = next
        }
        if let open = runStart {
            intervals.append(DateInterval(start: open, end: day))
        }
        return intervals
    }

    // MARK: - Helpers

    /// The key a model's figures are grouped under: its name without surrounding whitespace.
    public static func seriesName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func value(of item: CostUsageDailyReport.ModelBreakdown, metric: Metric) -> Double? {
        switch metric {
        case .cost: self.usable(item.costUSD)
        case .tokens: item.totalTokens.flatMap { $0 >= 0 ? Double($0) : nil }
        }
    }

    static func value(of entry: CostUsageDailyReport.Entry, metric: Metric) -> Double? {
        switch metric {
        case .cost: self.usable(entry.costUSD)
        case .tokens: entry.totalTokens.flatMap { $0 >= 0 ? Double($0) : nil }
        }
    }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
