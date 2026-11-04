import Foundation

/// Each series' share of a positive metric per calendar bucket, for a 100% stacked chart.
///
/// The largest series by total are kept and the rest fold into one Other series, so the chart stays readable
/// and palette slots can follow the same ranking. Non-finite and non-positive observations are ignored.
public struct SpendShareOverTime: Equatable, Sendable {
    public struct Observation: Equatable, Sendable {
        public let day: Date
        public let seriesID: String
        public let value: Double

        public init(day: Date, seriesID: String, value: Double) {
            self.day = day
            self.seriesID = seriesID
            self.value = value
        }
    }

    public struct Series: Equatable, Sendable, Identifiable {
        public let id: String
        /// Zero-based rank by total (descending, then ID ascending); Other always comes last.
        public let rank: Int
        public let total: Double
        /// Share of the whole range, from 0 to 1.
        public let share: Double
        /// The ranked series folded into Other; empty for a kept series.
        public let foldedSeriesIDs: [String]

        public var isOther: Bool {
            self.id == SpendShareOverTime.otherSeriesID
        }
    }

    public struct Point: Equatable, Sendable, Identifiable {
        public let bucketStart: Date
        public let seriesID: String
        public let value: Double
        /// This series' share of its bucket, from 0 to 1.
        public let share: Double
        /// Where this segment starts and ends in its bucket's stack, from 0 to 1.
        public let shareStart: Double
        public let shareEnd: Double

        public var id: String {
            "\(self.seriesID)|\(self.bucketStart.timeIntervalSinceReferenceDate)"
        }
    }

    /// Reserved ID for the folded series. The unit separator keeps it apart from any real model name.
    public static let otherSeriesID = "\u{1F}other"

    public let bucket: SpendInsightBucket
    /// Kept series in rank order, then Other when anything was folded.
    public let series: [Series]
    /// Stacked segments ordered by bucket, then by series rank. Buckets with no positive total are omitted.
    public let points: [Point]
    public let total: Double

    public var isEmpty: Bool {
        self.points.isEmpty
    }

    public init(observations: [Observation], topCount: Int, bucket: SpendInsightBucket, calendar: Calendar) {
        var totals: [String: Double] = [:]
        var valid: [Observation] = []
        for observation in observations where observation.value.isFinite && observation.value > 0 {
            totals[observation.seriesID, default: 0] += observation.value
            valid.append(observation)
        }
        let ranked = Self.rankedIDs(totals)
        var kept = Array(ranked.prefix(max(0, topCount)))
        var folded = Array(ranked.dropFirst(kept.count))
        // Folding a single series into Other would only hide its name.
        if folded.count == 1 {
            kept.append(contentsOf: folded)
            folded.removeAll()
        }

        let grandTotal = totals.values.reduce(0, +)
        guard grandTotal.isFinite, grandTotal > 0 else {
            self.bucket = bucket
            self.series = []
            self.points = []
            self.total = 0
            return
        }

        var series: [Series] = kept.enumerated().map { rank, id in
            let total = totals[id] ?? 0
            return Series(id: id, rank: rank, total: total, share: total / grandTotal, foldedSeriesIDs: [])
        }
        if !folded.isEmpty {
            let otherTotal = folded.reduce(0) { $0 + (totals[$1] ?? 0) }
            series.append(Series(
                id: Self.otherSeriesID,
                rank: kept.count,
                total: otherTotal,
                share: otherTotal / grandTotal,
                foldedSeriesIDs: folded))
        }

        let foldedIDs = Set(folded)
        var bucketValues: [Date: [String: Double]] = [:]
        for observation in valid {
            let start = bucket.start(of: observation.day, calendar: calendar)
            let id = foldedIDs.contains(observation.seriesID) ? Self.otherSeriesID : observation.seriesID
            bucketValues[start, default: [:]][id, default: 0] += observation.value
        }

        var points: [Point] = []
        for start in bucketValues.keys.sorted() {
            let values = bucketValues[start] ?? [:]
            let bucketTotal = values.values.reduce(0, +)
            guard bucketTotal.isFinite, bucketTotal > 0 else { continue }
            var cumulative = 0.0
            for entry in series {
                guard let value = values[entry.id], value > 0 else { continue }
                let share = value / bucketTotal
                let end = min(1, cumulative + share)
                points.append(Point(
                    bucketStart: start,
                    seriesID: entry.id,
                    value: value,
                    share: share,
                    shareStart: cumulative,
                    shareEnd: end))
                cumulative = end
            }
        }

        self.bucket = bucket
        self.series = series
        self.points = points
        self.total = grandTotal
    }

    /// IDs ordered by total descending, then ID ascending, matching the chart palette's stable order.
    static func rankedIDs(_ totals: [String: Double]) -> [String] {
        totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }
}
