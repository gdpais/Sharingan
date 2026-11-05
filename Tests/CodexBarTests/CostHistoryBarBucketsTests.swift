import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CostHistoryBarBucketsTests {
    private typealias Bar = CostHistoryBarBuckets.Bar

    @Test
    func `windows that fit keep one bar per day`() {
        for count in [1, 7, 30, 90] {
            let days = Self.days(count, from: "2026-01-05")
            #expect(CostHistoryBarBuckets.fitting(days) == days)
        }
    }

    @Test
    func `a year of days becomes weekly bars`() throws {
        // 2026-01-05 is a Monday, so 365 days are 52 full weeks and one Monday.
        let days = Self.days(365, from: "2026-01-05")
        let weeks = CostHistoryBarBuckets.fitting(days)
        #expect(weeks.count == 53)
        #expect(weeks.first?.date == "2026-01-05")
        #expect(weeks.dropLast().allSatisfy { $0.costUSD == 7 && $0.totalTokens == 700 })
        #expect(weeks.last?.costUSD == 1)
        // Every week starts on a Monday and the weeks keep the year's total.
        let calendar = Self.utcCalendar
        for week in weeks {
            let date = try #require(Self.date(week.date, calendar: calendar))
            #expect(calendar.component(.weekday, from: date) == 2)
        }
        #expect(weeks.compactMap(\.costUSD).reduce(0, +) == 365)
    }

    @Test
    func `a partial first week starts at its first day`() {
        // 2026-01-08 is a Thursday: Thursday to Sunday, then whole weeks.
        let weeks = CostHistoryBarBuckets.weekly(Self.days(11, from: "2026-01-08"))
        #expect(weeks.map(\.date) == ["2026-01-08", "2026-01-12"])
        #expect(weeks.map(\.costUSD) == [4, 7])
    }

    @Test
    func `weeks sum the days they know and keep incomplete markers`() {
        let days = [
            Bar(date: "2026-01-05", costUSD: 2, totalTokens: 200, incompleteRequestCount: 1),
            Bar(date: "2026-01-06", costUSD: nil, totalTokens: nil, incompleteRequestCount: 0),
            Bar(date: "2026-01-07", costUSD: 3, totalTokens: 100, incompleteRequestCount: 2),
            Bar(date: "2026-01-12", costUSD: nil, totalTokens: nil, incompleteRequestCount: 0),
            Bar(date: "2026-01-13", costUSD: nil, totalTokens: 50, incompleteRequestCount: 0),
        ]
        let weeks = CostHistoryBarBuckets.weekly(days)
        #expect(weeks == [
            Bar(date: "2026-01-05", costUSD: 5, totalTokens: 300, incompleteRequestCount: 3),
            // A week without any known cost stays unknown instead of reading as zero.
            Bar(date: "2026-01-12", costUSD: nil, totalTokens: 50, incompleteRequestCount: 0),
        ])
    }

    @Test
    func `unparseable days keep their own bar`() {
        let days = [
            Bar(date: "2026-01-05", costUSD: 1, totalTokens: 1, incompleteRequestCount: 0),
            Bar(date: "not-a-day", costUSD: 1, totalTokens: 1, incompleteRequestCount: 0),
            Bar(date: "2026-01-06", costUSD: 1, totalTokens: 1, incompleteRequestCount: 0),
        ]
        #expect(CostHistoryBarBuckets.weekly(days).map(\.date) == ["2026-01-05", "not-a-day", "2026-01-06"])
        #expect(CostHistoryBarBuckets.weekly([]).isEmpty)
    }

    @Test
    func `the in-card strip switches to weeks only past the daily limit`() {
        let fits = Self.days(CostHistoryBarBuckets.maximumDailyBars, from: "2026-01-05").map(Self.tuple)
        #expect(CostHistoryStripDays.fitting(fits).map(\.date) == fits.map(\.date))

        let year = Self.days(365, from: "2026-01-05").map(Self.tuple)
        let strip = CostHistoryStripDays.fitting(year)
        #expect(strip.count == 53)
        #expect(strip.first?.costUSD == 7)
        #expect(strip.first?.incompleteRequestCount == 0)
    }

    // MARK: - Fixtures

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func days(_ count: Int, from start: String) -> [Bar] {
        let calendar = self.utcCalendar
        guard let first = self.date(start, calendar: calendar) else { return [] }
        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let key = String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0)
            return Bar(date: key, costUSD: 1, totalTokens: 100, incompleteRequestCount: 0)
        }
    }

    private static func tuple(_ bar: Bar) -> CostHistoryStripDays.Day {
        (
            date: bar.date,
            costUSD: bar.costUSD,
            totalTokens: bar.totalTokens,
            incompleteRequestCount: bar.incompleteRequestCount)
    }
}
