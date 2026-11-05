import Foundation

/// Fits a daily cost strip into a fixed width: one bar per day while the days fit, one bar per week
/// beyond that, so a 365-day History window draws 53 bars instead of 365 hairlines.
public enum CostHistoryBarBuckets {
    /// One bar's figures. `date` is the first local day the bar covers (`yyyy-MM-dd`).
    public struct Bar: Equatable, Sendable {
        public let date: String
        public let costUSD: Double?
        public let totalTokens: Int?
        public let incompleteRequestCount: Int

        public init(date: String, costUSD: Double?, totalTokens: Int?, incompleteRequestCount: Int) {
            self.date = date
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.incompleteRequestCount = incompleteRequestCount
        }
    }

    /// More daily bars than this switch the strip to weekly bars.
    public static let maximumDailyBars = 90

    /// `days` unchanged while they fit in `maximumDailyBars`, otherwise their weekly sums.
    public static func fitting(_ days: [Bar], maximumDailyBars: Int = CostHistoryBarBuckets.maximumDailyBars) -> [Bar] {
        guard days.count > max(1, maximumDailyBars) else { return days }
        return self.weekly(days)
    }

    /// Sums consecutive days into ISO weeks (Monday to Sunday), chosen over the locale's first weekday
    /// so the strip matches the Monday labels of the cost history chart. Each week starts at its first
    /// listed day, so a partial first or last week says which days it holds.
    ///
    /// A week's cost or tokens are the sum of its known days and stay nil only when no day is known,
    /// as a single unknown day draws no bar. Days whose key does not parse keep their own bar.
    public static func weekly(_ days: [Bar]) -> [Bar] {
        let calendar = self.dayKeyCalendar
        var bars: [Bar] = []
        var group: [Bar] = []
        var groupWeek: String?
        for day in days {
            let week = self.weekKey(for: day.date, calendar: calendar)
            if week == nil || week != groupWeek, let bar = self.sum(group) {
                bars.append(bar)
                group = []
            }
            group.append(day)
            groupWeek = week
        }
        if let bar = self.sum(group) {
            bars.append(bar)
        }
        return bars
    }

    // MARK: - Helpers

    /// Day keys are already local days, so week math runs in UTC where every day is 24 hours.
    private static var dayKeyCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// The Monday that starts the ISO week of `dayKey`, or nil when the key does not parse.
    static func weekKey(for dayKey: String, calendar: Calendar) -> String? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        // Sunday is 1 and Monday is 2 in the Gregorian calendar.
        let daysSinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: date) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: monday)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0)
    }

    /// Nil for an empty group; a one-day group keeps its day's figures unchanged.
    private static func sum(_ group: [Bar]) -> Bar? {
        guard let first = group.first else { return nil }
        guard group.count > 1 else { return first }
        let costs = group.compactMap { day in day.costUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
        let tokens = group.compactMap { day in day.totalTokens.flatMap { $0 >= 0 ? $0 : nil } }
        return Bar(
            date: first.date,
            costUSD: costs.isEmpty ? nil : costs.reduce(0, +),
            totalTokens: tokens.isEmpty ? nil : CheckedSum.integers(tokens),
            incompleteRequestCount: CostUsageIncompleteRequests.sum(group.map(\.incompleteRequestCount)))
    }
}
