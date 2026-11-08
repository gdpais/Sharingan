import Foundation
import Testing
@testable import SharinganCore

struct SpendSeriesTrendsTests {
    @Test
    func `keeps the top series by total with zero filled daily points`() throws {
        let observations = [
            Self.observation("small", day: 1, value: 1),
            Self.observation("large", day: 0, value: 4),
            Self.observation("large", day: 2, value: 2),
            Self.observation("middle", day: 3, value: 3),
        ]

        let trends = Self.trends(observations, days: 4, topCount: 2)

        #expect(trends.trends.map(\.id) == ["large", "middle"])
        #expect(trends.trends.map(\.rank) == [1, 2])
        #expect(trends.trends.map(\.total) == [6, 3])
        #expect(trends.omittedSeriesCount == 1)
        let large = try #require(trends.trends.first)
        #expect(large.points.map(\.bucketStart) == (0..<4).map { Self.day($0) })
        #expect(large.points.map(\.value) == [4, 0, 2, 0])
        #expect(trends.maximumPointValue == 4)
    }

    @Test
    func `change compares the recent half of the range with the half before`() {
        let observations = [
            Self.observation("growing", day: 0, value: 4),
            Self.observation("growing", day: 4, value: 6),
            Self.observation("started", day: 5, value: 2),
            Self.observation("stopped", day: 1, value: 3),
            Self.observation("steady", day: 2, value: 1),
            Self.observation("steady", day: 3, value: 1),
        ]

        let trends = Self.trends(observations, days: 6, topCount: 5)
        let changes = Dictionary(uniqueKeysWithValues: trends.trends.map { ($0.id, $0.change) })

        #expect(trends.comparisonDayCount == 3)
        #expect(changes["growing"] == .percent(0.5))
        #expect(changes["started"] == .new)
        #expect(changes["stopped"] == .ended)
        #expect(changes["steady"] == .unchanged)
        let growing = trends.trends.first { $0.id == "growing" }
        #expect(growing?.previousTotal == 4)
        #expect(growing?.recentTotal == 6)
    }

    @Test
    func `an odd day count leaves the oldest day out of the comparison`() {
        let observations = [
            Self.observation("a", day: 0, value: 100),
            Self.observation("a", day: 1, value: 2),
            Self.observation("a", day: 4, value: 3),
        ]

        let trends = Self.trends(observations, days: 5, topCount: 5)

        #expect(trends.dayCount == 5)
        #expect(trends.comparisonDayCount == 2)
        #expect(trends.trends.first?.previousTotal == 2)
        #expect(trends.trends.first?.recentTotal == 3)
        #expect(trends.trends.first?.total == 105)
    }

    @Test
    func `a single day has nothing to compare`() {
        let trends = Self.trends([Self.observation("a", day: 0, value: 1)], days: 1, topCount: 5)

        #expect(trends.comparisonDayCount == 0)
        #expect(trends.trends.first?.change == .unavailable)
    }

    @Test
    func `a series whose source missed part of the comparison has no change`() {
        let observations = [
            Self.observation("full", day: 0, value: 1),
            Self.observation("full", day: 3, value: 2),
            Self.observation("late", day: 3, value: 2),
            Self.observation("stale", day: 0, value: 2),
            Self.observation("stale", day: 2, value: 1),
        ]

        let trends = SpendSeriesTrends(
            observations: observations,
            days: Self.day(0)...Self.day(3),
            bucket: .day,
            topCount: 5,
            calendar: Self.calendar,
            coverage: [
                "full": Self.day(0)...Self.day(3),
                "late": Self.day(2)...Self.day(3),
                "stale": Self.day(0)...Self.day(2),
            ])
        let changes = Dictionary(uniqueKeysWithValues: trends.trends.map { ($0.id, $0.change) })

        #expect(changes["full"] == .percent(1))
        // Started scanning inside the earlier half, so its spend there is unknown, not zero.
        #expect(changes["late"] == .unavailable)
        // Not scanned through the last day, so the recent half is a floor.
        #expect(changes["stale"] == .unavailable)
        #expect(trends.trends.first { $0.id == "late" }?.total == 2)
    }

    @Test
    func `weekly buckets sum their days and out of range values are ignored`() {
        let observations = [
            Self.observation("a", day: 0, value: 1),
            Self.observation("a", day: 6, value: 2),
            Self.observation("a", day: 7, value: 5),
            Self.observation("a", day: 20, value: 50),
            Self.observation("a", day: -1, value: 50),
            Self.observation("a", day: 3, value: .infinity),
        ]

        let trends = SpendSeriesTrends(
            observations: observations,
            days: Self.day(0)...Self.day(13),
            bucket: .week,
            topCount: 5,
            calendar: Self.calendar)

        #expect(trends.trends.first?.points.map(\.bucketStart) == [Self.day(0), Self.day(7)])
        #expect(trends.trends.first?.points.map(\.value) == [3, 5])
        #expect(trends.trends.first?.total == 8)
    }

    // MARK: - Fixtures

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Midnight UTC `offset` days after Monday 2026-06-01.
    private static func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_780_272_000 + TimeInterval(offset) * 86400)
    }

    private static func observation(_ id: String, day: Int, value: Double) -> SpendSeriesTrends.Observation {
        SpendSeriesTrends.Observation(seriesID: id, day: self.day(day), value: value)
    }

    private static func trends(
        _ observations: [SpendSeriesTrends.Observation],
        days: Int,
        topCount: Int) -> SpendSeriesTrends
    {
        SpendSeriesTrends(
            observations: observations,
            days: self.day(0)...self.day(days - 1),
            bucket: .day,
            topCount: topCount,
            calendar: self.calendar)
    }
}
