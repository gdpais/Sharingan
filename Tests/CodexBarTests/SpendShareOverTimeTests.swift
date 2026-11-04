import Foundation
import Testing
@testable import CodexBarCore

struct SpendShareOverTimeTests {
    @Test
    func `keeps the top series by total and folds the rest into other`() throws {
        let observations = [("a", 50.0), ("b", 30), ("c", 10), ("d", 6), ("e", 3), ("f", 1)].map { id, value in
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: id, value: value)
        }

        let share = SpendShareOverTime(observations: observations, topCount: 3, bucket: .day, calendar: Self.calendar)

        #expect(share.series.map(\.id) == ["a", "b", "c", SpendShareOverTime.otherSeriesID])
        #expect(share.series.map(\.rank) == [0, 1, 2, 3])
        #expect(share.series.map(\.total) == [50, 30, 10, 10])
        #expect(share.series.map(\.share) == [0.5, 0.3, 0.1, 0.1])
        let other = try #require(share.series.last)
        #expect(other.isOther)
        #expect(other.foldedSeriesIDs == ["d", "e", "f"])
        #expect(share.total == 100)
    }

    @Test
    func `a single leftover series keeps its name instead of folding`() {
        let observations = [("a", 5.0), ("b", 4), ("c", 3), ("d", 2)].map { id, value in
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: id, value: value)
        }

        let share = SpendShareOverTime(observations: observations, topCount: 3, bucket: .day, calendar: Self.calendar)

        #expect(share.series.map(\.id) == ["a", "b", "c", "d"])
        #expect(share.series.allSatisfy { !$0.isOther && $0.foldedSeriesIDs.isEmpty })
    }

    @Test
    func `each bucket stacks to one in rank order with other on top`() {
        let observations = [
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "a", value: 6),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "b", value: 2),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "c", value: 1),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "d", value: 1),
            SpendShareOverTime.Observation(day: Self.day(1), seriesID: "b", value: 3),
            SpendShareOverTime.Observation(day: Self.day(1), seriesID: "a", value: 1),
        ]

        let share = SpendShareOverTime(observations: observations, topCount: 2, bucket: .day, calendar: Self.calendar)
        let other = SpendShareOverTime.otherSeriesID

        #expect(share.points.map(\.seriesID) == ["a", "b", other, "a", "b"])
        #expect(share.points.map(\.bucketStart) == [Self.day(0), Self.day(0), Self.day(0), Self.day(1), Self.day(1)])
        #expect(share.points.map(\.share) == [0.6, 0.2, 0.2, 0.25, 0.75])
        #expect(share.points.map(\.shareStart) == [0, 0.6, 0.8, 0, 0.25])
        #expect(share.points.map(\.shareEnd) == [0.6, 0.8, 1, 0.25, 1])
    }

    @Test
    func `weekly buckets merge the days of each week`() {
        // Day 0 is a Monday; days 0 and 6 share a week, day 7 starts the next one.
        let observations = [
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "a", value: 1),
            SpendShareOverTime.Observation(day: Self.day(6), seriesID: "b", value: 3),
            SpendShareOverTime.Observation(day: Self.day(7), seriesID: "a", value: 2),
        ]

        let share = SpendShareOverTime(observations: observations, topCount: 5, bucket: .week, calendar: Self.calendar)

        #expect(share.points.map(\.bucketStart) == [Self.day(0), Self.day(0), Self.day(7)])
        #expect(share.points.map(\.seriesID) == ["a", "b", "a"])
        #expect(share.points.map(\.share) == [0.25, 0.75, 1])
    }

    @Test
    func `ties rank by id and invalid values are ignored`() {
        let observations = [
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "b", value: 2),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "a", value: 2),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "c", value: -4),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "d", value: .nan),
            SpendShareOverTime.Observation(day: Self.day(0), seriesID: "e", value: 0),
        ]

        let share = SpendShareOverTime(observations: observations, topCount: 5, bucket: .day, calendar: Self.calendar)

        #expect(share.series.map(\.id) == ["a", "b"])
        #expect(SpendShareOverTime(observations: [], topCount: 5, bucket: .day, calendar: Self.calendar).isEmpty)
        #expect(SpendShareOverTime(
            observations: Array(observations.suffix(3)),
            topCount: 5,
            bucket: .day,
            calendar: Self.calendar).series.isEmpty)
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
}
