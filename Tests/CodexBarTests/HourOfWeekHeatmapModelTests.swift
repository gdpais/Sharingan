import CodexBarCore
import Foundation
import Testing

struct HourOfWeekHeatmapModelTests {
    @Test
    func `a week of samples folds into weekday and hour cells`() throws {
        let calendar = try Self.calendar("UTC")
        // 2026-11-01 is a Sunday.
        let sunday = try Self.date("2026-11-01T00:00:00Z")
        var samples: [HourOfWeekHeatmapModel.Sample] = []
        for day in 0..<7 {
            let start = sunday.addingTimeInterval(Double(day) * 86400)
            samples.append(.init(hour: start.addingTimeInterval(9 * 3600), cost: Double(day + 1), tokens: 100))
            samples.append(.init(hour: start.addingTimeInterval(14 * 3600), cost: 0.5))
        }
        // The following Tuesday adds to the same weekday and hour.
        samples.append(.init(hour: sunday.addingTimeInterval(9 * 86400 + 9 * 3600), cost: 10, tokens: 50))

        let model = HourOfWeekHeatmapModel(samples: samples, calendar: calendar)

        #expect(model.cells.count == 168)
        #expect(model.cells.map(\.id) == Array(0..<168))
        #expect(model.weekdays == [1, 2, 3, 4, 5, 6, 7])
        #expect(model.sampleCount == 15)
        #expect(model.totalCost == 41.5)
        #expect(model.totalTokens == 750)
        let tuesday = try #require(model.cell(weekday: 3, hour: 9))
        #expect(tuesday.cost == 13)
        #expect(tuesday.sampleCount == 2)
        #expect(tuesday.tokens == 150)
        #expect(tuesday.share == 13 / 41.5)
        #expect(tuesday.intensity == 1)
        #expect(model.maxCost == 13)
        #expect(model.maxTokens == 150)
        #expect(model.busiestCell == tuesday)
        #expect(model.cell(weekday: 3, hour: 14)?.cost == 0.5)
        #expect(model.cell(weekday: 3, hour: 14)?.tokens == nil)
        let quiet = try #require(model.cell(weekday: 3, hour: 10))
        #expect(quiet.sampleCount == 0)
        #expect(quiet.cost == 0)
        #expect(abs(model.cells.reduce(0) { $0 + $1.share } - 1) < 1e-12)
        // Sunday 1 + 0.5 and Saturday 7 + 0.5.
        #expect(model.weekendCost == 9)
        #expect(model.weekendShare == 9 / 41.5)
        #expect(Set(model.cells.filter(\.isWeekend).map(\.weekday)) == [1, 7])
        let saturday = try #require(model.cell(weekday: 7, hour: 9))
        let monday = try #require(model.cell(weekday: 2, hour: 9))
        #expect(model.level(of: tuesday) == 4)
        #expect(model.level(of: saturday) == 3)
        #expect(model.level(of: monday) == 1)
        #expect(model.level(of: quiet) == 0)
    }

    @Test
    func `the same instants follow the statistics time zone`() throws {
        // Monday 2026-11-02 and Friday 2026-11-06, both at 20:00 UTC.
        let samples = try ["2026-11-02T20:00:00Z", "2026-11-06T20:00:00Z"].map {
            try HourOfWeekHeatmapModel.Sample(hour: Self.date($0), cost: 2)
        }
        let utc = try HourOfWeekHeatmapModel(samples: samples, calendar: Self.calendar("UTC"))
        let tokyo = try HourOfWeekHeatmapModel(samples: samples, calendar: Self.calendar("Asia/Tokyo"))
        let kolkata = try HourOfWeekHeatmapModel(samples: samples, calendar: Self.calendar("Asia/Kolkata"))
        let pacific = try HourOfWeekHeatmapModel(samples: samples, calendar: Self.calendar("America/Los_Angeles"))

        #expect(utc.cell(weekday: 2, hour: 20)?.cost == 2)
        #expect(utc.cell(weekday: 6, hour: 20)?.cost == 2)
        #expect(utc.weekendShare == 0)
        // UTC+9 moves both samples into the next morning; Friday evening becomes Saturday.
        #expect(tokyo.cell(weekday: 3, hour: 5)?.cost == 2)
        #expect(tokyo.cell(weekday: 7, hour: 5)?.cost == 2)
        #expect(tokyo.weekendShare == 0.5)
        // Half-hour offsets floor to the wall-clock hour.
        #expect(kolkata.cell(weekday: 3, hour: 1)?.cost == 2)
        #expect(kolkata.cell(weekday: 7, hour: 1)?.cost == 2)
        // Standard time has resumed in Los Angeles (UTC-8).
        #expect(pacific.cell(weekday: 2, hour: 12)?.cost == 2)
        #expect(pacific.cell(weekday: 6, hour: 12)?.cost == 2)
        for model in [utc, tokyo, kolkata, pacific] {
            #expect(model.totalCost == 4)
            #expect(model.cells.count(where: { $0.sampleCount > 0 }) == 2)
        }
    }

    @Test(arguments: [
        ("America/New_York", 2026, 3, 8, 23),
        ("America/New_York", 2026, 11, 1, 25),
        ("Australia/Lord_Howe", 2026, 10, 4, 24),
    ])
    func `daylight saving days fold wall clock hours without losing samples`(
        zone: String, year: Int, month: Int, day: Int, sampleCount: Int) throws
    {
        let calendar = try Self.calendar(zone)
        let noon = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        let start = calendar.startOfDay(for: noon)
        let end = try calendar.startOfDay(for: #require(calendar.date(byAdding: .day, value: 1, to: noon)))
        var samples: [HourOfWeekHeatmapModel.Sample] = []
        var hour = start
        while hour < end {
            samples.append(.init(hour: hour, cost: 1))
            hour = hour.addingTimeInterval(3600)
        }
        #expect(samples.count == sampleCount)

        let model = HourOfWeekHeatmapModel(samples: samples, calendar: calendar)

        #expect(model.sampleCount == sampleCount)
        #expect(model.totalCost == Double(sampleCount))
        // Every sample stays on the transition Sunday.
        #expect(model.cells.filter { $0.weekday == 1 }.reduce(0) { $0 + $1.sampleCount } == sampleCount)
        #expect(model.cells.filter { $0.weekday != 1 }.allSatisfy { $0.sampleCount == 0 })
        #expect(model.weekendShare == 1)
        if sampleCount == 23 {
            // 02:00 does not exist when clocks spring forward.
            #expect(model.cell(weekday: 1, hour: 2)?.sampleCount == 0)
            #expect(model.busiestCell?.hour == 0)
        }
        if sampleCount == 25 {
            // Both 01:00 hours fold into one wall-clock cell.
            #expect(model.cell(weekday: 1, hour: 1)?.sampleCount == 2)
            #expect(model.cell(weekday: 1, hour: 1)?.cost == 2)
            #expect(model.busiestCell?.hour == 1)
        }
    }

    @Test(arguments: [
        (1, [1, 2, 3, 4, 5, 6, 7]),
        (2, [2, 3, 4, 5, 6, 7, 1]),
    ])
    func `rows start at the calendar first weekday`(firstWeekday: Int, weekdays: [Int]) throws {
        var calendar = try Self.calendar("UTC")
        calendar.firstWeekday = firstWeekday
        let sunday = try Self.date("2026-11-01T10:00:00Z")
        let monday = sunday.addingTimeInterval(86400)
        let model = HourOfWeekHeatmapModel(
            samples: [.init(hour: sunday, cost: 1), .init(hour: monday, cost: 2)],
            calendar: calendar)

        #expect(model.weekdays == weekdays)
        #expect(model.cells.map(\.id) == Array(0..<168))
        #expect(model.cells.first?.weekday == weekdays[0])
        #expect(model.cells.last?.weekday == weekdays[6])
        #expect(model.cell(weekday: 1, hour: 10)?.row == weekdays.firstIndex(of: 1))
        #expect(model.cell(weekday: 2, hour: 10)?.row == weekdays.firstIndex(of: 2))
        #expect(model.cell(row: 0, hour: 10)?.cost == (firstWeekday == 2 ? 2.0 : 1.0))
        #expect(model.cell(row: 6, hour: 10)?.cost == (firstWeekday == 2 ? 1.0 : 0.0))
        #expect(model.cell(row: 7, hour: 0) == nil)
        #expect(model.cell(row: 0, hour: 24) == nil)
        // Order changes rows only, never totals.
        #expect(model.busiestCell?.weekday == 2)
        #expect(model.weekendShare == 1.0 / 3.0)
    }

    @Test
    func `empty input yields an empty grid without a busiest cell or weekend share`() throws {
        let model = try HourOfWeekHeatmapModel(samples: [], calendar: Self.calendar("UTC"))

        #expect(model.isEmpty)
        #expect(model.cells.count == 168)
        #expect(model.cells.allSatisfy {
            $0.cost == 0 && $0.sampleCount == 0 && $0.tokens == nil && $0.share == 0 && $0.intensity == 0
        })
        #expect(model.cells.allSatisfy { model.level(of: $0) == 0 })
        #expect(model.totalCost == 0)
        #expect(model.maxCost == 0)
        #expect(model.totalTokens == nil)
        #expect(model.maxTokens == nil)
        #expect(model.busiestCell == nil)
        #expect(model.weekendCost == 0)
        #expect(model.weekendShare == nil)
    }

    @Test
    func `zero and invalid costs keep their samples without inventing spend`() throws {
        let hour = try Self.date("2026-11-03T08:00:00Z")
        let model = try HourOfWeekHeatmapModel(
            samples: [
                .init(hour: hour, cost: 0),
                .init(hour: hour, cost: nil, tokens: 5),
                .init(hour: hour, cost: -1, tokens: -3),
                .init(hour: hour, cost: Double.nan),
                .init(hour: hour, cost: Double.infinity),
            ],
            calendar: Self.calendar("UTC"))

        #expect(!model.isEmpty)
        #expect(model.sampleCount == 5)
        #expect(model.cell(weekday: 3, hour: 8)?.sampleCount == 5)
        #expect(model.totalCost == 0)
        #expect(model.totalTokens == 5)
        #expect(model.busiestCell == nil)
        #expect(model.weekendShare == nil)
        #expect(model.cells.allSatisfy { model.level(of: $0) == 0 })
    }

    private static func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    private static func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }
}
