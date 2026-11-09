import Foundation
import SharinganCore

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

    /// Hover and accessibility text for a weekly strip: each bar names every day it sums ("Mar 2 – 8, 2026"),
    /// not only its first day. `days` are the strip's days before `fitting`; a daily strip comes back unchanged.
    static func labelingWeeks(
        _ points: [InlineUsageDashboardModel.Point],
        days: [Day],
        locale: Locale = sharinganLocalizedLocale()) -> [InlineUsageDashboardModel.Point]
    {
        guard days.count > CostHistoryBarBuckets.maximumDailyBars, let lastDay = days.last?.date else { return points }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.timeZone = parser.timeZone
        formatter.dateTemplate = "yMMMd"
        return points.enumerated().map { index, point in
            // Day keys are local days parsed in UTC, where every day is 24 hours.
            let lastCoveredDay: Date? = index + 1 < points.count
                ? parser.date(from: points[index + 1].id).map { $0.addingTimeInterval(-86400) }
                : parser.date(from: lastDay)
            guard let start = parser.date(from: point.id), let end = lastCoveredDay, end > start else { return point }
            let label = formatter.string(from: start, to: end)
            let hoverDetail = point.hoverDetail.map { detail in
                InlineUsageDashboardModel.HoverDetail(
                    dateLabel: label,
                    cost: detail.cost,
                    tokenCount: detail.tokenCount,
                    currencyCode: detail.currencyCode,
                    incompleteRequestCount: detail.incompleteRequestCount,
                    tokensOnly: detail.tokensOnly)
            }
            return InlineUsageDashboardModel.Point(
                id: point.id,
                label: point.label,
                value: point.value,
                accessibilityValue: hoverDetail?.summary ?? "\(label): \(L("Unknown"))",
                hoverDetail: hoverDetail)
        }
    }
}
