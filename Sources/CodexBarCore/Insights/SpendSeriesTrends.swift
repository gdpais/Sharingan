import Foundation

/// The top series of a range as small trend lines, each with the change between the range's two halves.
///
/// The change compares the most recent half of the days with the half before it, so it needs no data outside
/// the range. With an odd day count the oldest day only appears in the lines. Non-finite, non-positive and
/// out-of-range observations are ignored. A series whose `coverage` misses any day of the comparison has no
/// change, because days its source never scanned would otherwise read as zero spend.
public struct SpendSeriesTrends: Equatable, Sendable {
    public struct Observation: Equatable, Sendable {
        public let seriesID: String
        public let day: Date
        public let value: Double

        public init(seriesID: String, day: Date, value: Double) {
            self.seriesID = seriesID
            self.day = day
            self.value = value
        }
    }

    public struct Point: Equatable, Sendable, Identifiable {
        public let bucketStart: Date
        public let value: Double

        public var id: Date {
            self.bucketStart
        }
    }

    public struct Trend: Equatable, Sendable, Identifiable {
        public let id: String
        /// One-based rank by total (descending, then ID ascending).
        public let rank: Int
        public let total: Double
        /// Total over the most recent `comparisonDayCount` days.
        public let recentTotal: Double
        /// Total over the `comparisonDayCount` days before those.
        public let previousTotal: Double
        public let change: CodexModelsComparison
        /// One point per bucket in the range, zero where the series had nothing.
        public let points: [Point]
    }

    /// Upper bound on enumerated days, so a corrupt range cannot loop for long.
    public static let maximumDayCount = 3660

    public let bucket: SpendInsightBucket
    public let dayCount: Int
    /// Days in each half of the comparison; zero when the range is a single day.
    public let comparisonDayCount: Int
    public let trends: [Trend]
    /// Series with spend in the range that did not make the top list.
    public let omittedSeriesCount: Int

    /// Largest bucket value across all trends, for a shared y scale.
    public var maximumPointValue: Double {
        self.trends.flatMap(\.points).map(\.value).max() ?? 0
    }

    public init(
        observations: [Observation],
        days range: ClosedRange<Date>,
        bucket: SpendInsightBucket,
        topCount: Int,
        calendar: Calendar,
        coverage: [String: ClosedRange<Date>] = [:])
    {
        let days = Self.days(in: range, calendar: calendar)
        let dayIndex = Dictionary(
            days.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first })

        var dailyBySeries: [String: [Double]] = [:]
        for observation in observations where observation.value.isFinite && observation.value > 0 {
            // Callers usually pass day starts already; only other times need the calendar.
            guard let index = dayIndex[observation.day] ?? dayIndex[calendar.startOfDay(for: observation.day)]
            else { continue }
            // Mutate in place: copying the row out and back would copy it once per observation.
            dailyBySeries[observation.seriesID, default: Array(repeating: 0, count: days.count)][index] +=
                observation.value
        }

        var totals: [String: Double] = [:]
        for (id, daily) in dailyBySeries {
            totals[id] = daily.reduce(0, +)
        }
        let ranked = totals
            .filter { $0.value.isFinite && $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
        let kept = Array(ranked.prefix(max(0, topCount)))

        let half = days.count / 2
        let recentRange = (days.count - half)..<days.count
        let previousRange = (days.count - 2 * half)..<(days.count - half)
        // Every day the change reads: the earlier half's first day through the range's last day.
        let comparisonSpan: ClosedRange<Date>? = half > 0 ? days[previousRange.lowerBound]...days[days.count - 1] : nil

        var bucketStarts: [Date] = []
        var bucketIndexByDay: [Int] = []
        for day in days {
            let start = bucket.start(of: day, calendar: calendar)
            if bucketStarts.last != start {
                bucketStarts.append(start)
            }
            bucketIndexByDay.append(bucketStarts.count - 1)
        }

        var trends: [Trend] = []
        for (offset, id) in kept.enumerated() {
            guard let daily = dailyBySeries[id], daily.count == days.count else { continue }
            var bucketTotals = Array(repeating: 0.0, count: bucketStarts.count)
            for (index, value) in daily.enumerated() where index < bucketIndexByDay.count {
                bucketTotals[bucketIndexByDay[index]] += value
            }
            let recent = recentRange.reduce(0.0) { $0 + daily[$1] }
            let previous = previousRange.reduce(0.0) { $0 + daily[$1] }
            var isComparable = false
            if let comparisonSpan {
                isComparable = Self.covers(coverage[id], span: comparisonSpan, calendar: calendar)
            }
            trends.append(Trend(
                id: id,
                rank: offset + 1,
                total: totals[id] ?? 0,
                recentTotal: recent,
                previousTotal: previous,
                change: isComparable ? CodexModelsComparison.make(current: recent, previous: previous) : .unavailable,
                points: zip(bucketStarts, bucketTotals).map { Point(bucketStart: $0, value: $1) }))
        }

        self.bucket = bucket
        self.dayCount = days.count
        self.comparisonDayCount = half
        self.trends = trends
        self.omittedSeriesCount = ranked.count - kept.count
    }

    /// Whether `coverage` includes every day of `span`; a series without coverage spans the range.
    private static func covers(_ coverage: ClosedRange<Date>?, span: ClosedRange<Date>, calendar: Calendar) -> Bool {
        guard let coverage else { return true }
        return calendar.startOfDay(for: coverage.lowerBound) <= span.lowerBound
            && calendar.startOfDay(for: coverage.upperBound) >= span.upperBound
    }

    /// Day starts from the range's first day through its last day, inclusive.
    static func days(in range: ClosedRange<Date>, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        while cursor <= last, days.count < Self.maximumDayCount {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let nextStart = calendar.startOfDay(for: next)
            guard nextStart > cursor else { break }
            cursor = nextStart
        }
        return days
    }
}
