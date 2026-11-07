import CodexBarCore

/// Fits the in-card spend strip into the card: daily bars while they fit, weekly sums beyond
/// `CostHistoryBarBuckets.maximumDailyBars`, so a 365-day History window draws 53 bars, not 365.
enum CostHistoryStripDays {
    typealias Day = (date: String, costUSD: Double?, totalTokens: Int?, incompleteRequestCount: Int)

    static func fitting(_ days: [Day]) -> [Day] {
        guard days.count > CostHistoryBarBuckets.maximumDailyBars else { return days }
        let bars = days.map { day in
            CostHistoryBarBuckets.Bar(
                date: day.date,
                costUSD: day.costUSD,
                totalTokens: day.totalTokens,
                incompleteRequestCount: day.incompleteRequestCount)
        }
        return CostHistoryBarBuckets.fitting(bars).map { bar in
            (
                date: bar.date,
                costUSD: bar.costUSD,
                totalTokens: bar.totalTokens,
                incompleteRequestCount: bar.incompleteRequestCount)
        }
    }
}
