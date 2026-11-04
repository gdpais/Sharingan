import Foundation
import Testing
@testable import CodexBarCore

struct SpendInsightTilesTests {
    // MARK: - Prompt split

    @Test
    func `prompt split reads inclusive and disjoint token conventions`() throws {
        // Codex style: cache reads are part of input, so the total is input plus output.
        let codex = try #require(SpendInsightPromptSplit.normalized(Self.sample(
            input: 1000, cacheRead: 600, output: 200, total: 1200)))
        #expect(codex == SpendInsightPromptSplit(promptTokens: 1000, cachedTokens: 600))

        // Claude style: input, cache reads and cache writes are disjoint classes.
        let claude = try #require(SpendInsightPromptSplit.normalized(Self.sample(
            input: 100, cacheRead: 600, cacheWrite: 300, output: 200, total: 1200)))
        #expect(claude == SpendInsightPromptSplit(promptTokens: 1000, cachedTokens: 600))

        // Reasoning on top of the total still settles the convention.
        let reasoning = try #require(SpendInsightPromptSplit.normalized(Self.sample(
            input: 1000, cacheRead: 600, output: 200, reasoning: 50, total: 1250)))
        #expect(reasoning == SpendInsightPromptSplit(promptTokens: 1000, cachedTokens: 600))
    }

    @Test
    func `prompt split leaves out samples the total cannot settle`() {
        #expect(SpendInsightPromptSplit.normalized(Self.sample(
            input: 1000, cacheRead: 600, output: 200, total: 5000)) == nil)
        #expect(SpendInsightPromptSplit.normalized(Self.sample(
            input: 1000, cacheRead: 600, output: 200, total: nil)) == nil)
        #expect(SpendInsightPromptSplit.normalized(Self.sample(
            input: nil, cacheRead: 600, output: 200, total: 800)) == nil)
        // Without a total, cache reads larger than input can only be disjoint.
        #expect(SpendInsightPromptSplit.normalized(Self.sample(
            input: 100, cacheRead: 600, output: 200, total: nil))
            == SpendInsightPromptSplit(promptTokens: 700, cachedTokens: 600))
        // Without cache classes both conventions agree.
        #expect(SpendInsightPromptSplit.normalized(Self.sample(
            input: 400, cacheRead: nil, output: 200, total: nil))
            == SpendInsightPromptSplit(promptTokens: 400, cachedTokens: 0))
    }

    // MARK: - Formulas

    @Test
    func `cache hit rate combines conventions and skips sources without cache reads`() throws {
        let tiles = Self.tiles(samples: [
            Self.sample(source: "codex", day: 0, input: 1000, cacheRead: 600, output: 100, total: 1100),
            Self.sample(
                source: "claude",
                day: 1,
                input: 100,
                cacheRead: 800,
                cacheWrite: 100,
                output: 100,
                total: 1100),
            // Codex reports cache reads on other days, so a missing class here is zero.
            Self.sample(source: "codex", day: 2, input: 1000, cacheRead: nil, output: 0, total: 1000),
            // This source never reports cache reads and stays out of the rate.
            Self.sample(source: "plain", day: 3, input: 5000, cacheRead: nil, output: 0, total: 5000),
        ])
        let rate = try #require(tiles.cacheHitRate)
        #expect(abs(rate.value - 1400.0 / 3000.0) < 1e-12)
    }

    @Test
    func `cost per million tokens pairs spend with tokens from the same samples`() throws {
        let tiles = Self.tiles(samples: [
            Self.sample(day: 0, cost: 3, total: 1_000_000),
            Self.sample(day: 1, cost: 2, total: nil),
            Self.sample(day: 2, cost: nil, total: 500_000),
            Self.sample(day: 3, cost: 1, total: 1_000_000),
        ])
        let tile = try #require(tiles.costPerMillionTokens)
        #expect(tile.value == 2)
        #expect(tiles.apiEquivalentCost == 6)
    }

    @Test
    func `top model share divides by all spend including unattributed spend`() throws {
        let tiles = Self.tiles(samples: [
            Self.sample(day: 0, cost: 10, models: [("claude:model-a", "model-a", 6), ("claude:model-b", "model-b", 2)]),
            Self.sample(day: 1, cost: 10, models: [("claude:model-b", "model-b", 10)]),
        ])
        let share = try #require(tiles.topModelShare)
        #expect(share.modelID == "claude:model-b")
        #expect(share.modelName == "model-b")
        #expect(share.tile.value == 0.6)
    }

    @Test
    func `top model share keeps providers apart breaks ties by name and never exceeds one`() throws {
        // Merged by name, "shared" would lead with 7; per provider, "other" leads with 5.
        let split = try #require(Self.tiles(samples: [
            Self.sample(day: 0, cost: 7, models: [("codex:shared", "shared", 4), ("claude:shared", "shared", 3)]),
            Self.sample(day: 1, cost: 5, models: [("claude:other", "other", 5)]),
        ]).topModelShare)
        #expect(split.modelID == "claude:other")
        #expect(abs(split.tile.value - 5.0 / 12.0) < 1e-12)

        let tie = try #require(Self.tiles(samples: [
            Self.sample(day: 0, cost: 4, models: [("codex:zeta", "zeta", 2), ("codex:alpha", "alpha", 2)]),
        ]).topModelShare)
        #expect(tie.modelName == "alpha")

        let overclaimed = try #require(Self.tiles(samples: [
            Self.sample(day: 0, cost: 5, models: [("codex:alpha", "alpha", 8)]),
        ]).topModelShare)
        #expect(overclaimed.tile.value == 1)
    }

    @Test
    func `plan value divides API equivalent spend by the prorated plan price`() throws {
        let month = Self.tiles(
            samples: [Self.sample(day: 0, cost: 1000), Self.sample(day: 29, cost: 300)],
            planMonthlyPrice: 200)
        let monthValue = try #require(month.planValue)
        #expect(monthValue.value == 6.5)

        let halfMonth = Self.tiles(
            dayCount: 15,
            samples: [Self.sample(day: 3, cost: 650)],
            planMonthlyPrice: 200)
        let halfMonthValue = try #require(halfMonth.planValue)
        #expect(halfMonthValue.value == 6.5)
    }

    @Test
    func `plan value is nil without a usable plan price or spend`() {
        let samples = [Self.sample(day: 0, cost: 1300)]
        let noPrice = Self.tiles(samples: samples, planMonthlyPrice: nil)
        #expect(noPrice.planValue == nil)
        #expect(noPrice.apiEquivalentCost == 1300)
        for price in [0, -200, Double.nan, Double.infinity] {
            #expect(Self.tiles(samples: samples, planMonthlyPrice: price).planValue == nil)
        }
        let noSpend = Self.tiles(samples: [Self.sample(day: 0, cost: nil, total: 100)], planMonthlyPrice: 200)
        #expect(noSpend.apiEquivalentCost == nil)
        #expect(noSpend.planValue == nil)
    }

    @Test
    func `empty inputs and zero denominators produce no tiles`() {
        let empty = SpendInsightTiles(inputs: SpendInsightInputs(), calendar: Self.calendar, planMonthlyPrice: 200)
        #expect(empty.trendBucketCount == 0)
        #expect(empty.apiEquivalentCost == nil)
        #expect(empty.planValue == nil)
        #expect(empty.cacheHitRate == nil)
        #expect(empty.costPerMillionTokens == nil)
        #expect(empty.topModelShare == nil)

        let zeroDays = SpendInsightTiles(
            inputs: SpendInsightInputs(
                period: SpendInsightPeriod(start: Self.start, dayCount: 0),
                samples: [Self.sample(day: 0, cost: 5, total: 10)]),
            calendar: Self.calendar,
            planMonthlyPrice: 200)
        #expect(zeroDays.trendBucketCount == 0)
        #expect(zeroDays.costPerMillionTokens == nil)

        let zeros = Self.tiles(samples: [
            Self.sample(source: "codex", day: 0, cost: 0, input: 0, cacheRead: 0, output: 0, total: 0),
        ])
        #expect(zeros.apiEquivalentCost == 0)
        #expect(zeros.costPerMillionTokens == nil)
        #expect(zeros.cacheHitRate == nil)
        #expect(zeros.topModelShare == nil)
    }

    // MARK: - Trend

    @Test
    func `trend splits the range into twelve buckets and keeps edge days`() throws {
        let tiles = Self.tiles(samples: [
            Self.sample(day: -1, cost: 100, total: 1_000_000),
            Self.sample(day: 0, cost: 1, total: 1_000_000),
            Self.sample(day: 2, cost: 3, total: 1_000_000),
            Self.sample(day: 3, cost: 5, total: 1_000_000),
            Self.sample(day: 29, cost: 7, total: 1_000_000),
            Self.sample(day: 30, cost: 100, total: 1_000_000),
        ])
        #expect(tiles.trendBucketCount == 12)
        let tile = try #require(tiles.costPerMillionTokens)
        #expect(tile.value == 4)
        #expect(tile.trend.count == 12)
        #expect(tile.trend[0] == 2)
        #expect(tile.trend[1] == 5)
        #expect(tile.trend[11] == 7)
        #expect(tile.trend[2...10].allSatisfy { $0 == nil })
    }

    @Test
    func `uneven buckets prorate plan value by their own day count`() throws {
        // 30 days in 12 buckets alternate three and two days, so equal daily spend reads flat.
        let samples = (0..<30).map { Self.sample(day: $0, cost: 10) }
        let tile = try #require(Self.tiles(samples: samples, planMonthlyPrice: 300).planValue)
        #expect(tile.value == 1)
        #expect(tile.trend.count == 12)
        for value in tile.trend {
            #expect(abs((value ?? 0) - 1) < 1e-12)
        }
    }

    @Test
    func `short ranges use one bucket per day`() throws {
        let week = Self.tiles(dayCount: 7, samples: [
            Self.sample(day: 0, cost: 1, total: 1_000_000),
            Self.sample(day: 6, cost: 2, total: 1_000_000),
        ])
        #expect(week.trendBucketCount == 7)
        let trend = try #require(week.costPerMillionTokens).trend
        #expect(trend == [1, nil, nil, nil, nil, nil, 2])

        let today = Self.tiles(dayCount: 1, samples: [Self.sample(day: 0, cost: 1, total: 1_000_000)])
        let todayCost = try #require(today.costPerMillionTokens)
        #expect(todayCost.trend == [1])
    }

    @Test
    func `buckets follow calendar days across a daylight saving change`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        // 2026-03-08 is 23 hours long in Los Angeles.
        let springForward = try #require(calendar.date(byAdding: .day, value: 7, to: start))
        let lastDay = try #require(calendar.date(byAdding: .day, value: 13, to: start))
        let inputs = SpendInsightInputs(
            period: SpendInsightPeriod(start: start, dayCount: 14),
            samples: [
                SpendInsightSample(sourceID: "codex", day: springForward, cost: 1, totalTokens: 1_000_000),
                SpendInsightSample(sourceID: "codex", day: lastDay, cost: 3, totalTokens: 1_000_000),
            ])
        let tiles = SpendInsightTiles(inputs: inputs, calendar: calendar, planMonthlyPrice: nil)
        let trend = try #require(tiles.costPerMillionTokens).trend
        #expect(trend.count == 12)
        #expect(trend[6] == 1)
        #expect(trend[11] == 3)
    }

    // MARK: - Delta

    @Test
    func `delta compares with the previous period of equal length`() throws {
        let tiles = Self.tiles(
            dayCount: 7,
            samples: [
                Self.sample(source: "codex", day: 0, cost: 4, input: 1000, cacheRead: 600, output: 0, total: 1000),
                Self.sample(source: "codex", day: 6, cost: 4, input: 1000, cacheRead: 600, output: 0, total: 1000),
            ],
            previous: [
                Self.sample(source: "codex", day: -8, cost: 50, input: 1000, cacheRead: 0, output: 0, total: 1000),
                Self.sample(source: "codex", day: -7, cost: 1, input: 1000, cacheRead: 400, output: 0, total: 1000),
                Self.sample(source: "codex", day: -1, cost: 1, input: 1000, cacheRead: 400, output: 0, total: 1000),
                Self.sample(source: "codex", day: 0, cost: 50, input: 1000, cacheRead: 0, output: 0, total: 1000),
            ])
        let cache = try #require(tiles.cacheHitRate)
        #expect(cache.value == 0.6)
        #expect(cache.previousValue == 0.4)
        #expect(abs((cache.delta ?? 0) - 0.2) < 1e-12)

        let cost = try #require(tiles.costPerMillionTokens)
        #expect(cost.value == 4000)
        #expect(cost.previousValue == 1000)
        #expect(cost.relativeDelta == 3)
    }

    @Test
    func `delta is nil when the previous period is unavailable or empty`() throws {
        let samples = [Self.sample(day: 0, cost: 4, total: 1_000_000)]
        let uncovered = try #require(Self.tiles(dayCount: 7, samples: samples, previous: nil).costPerMillionTokens)
        #expect(uncovered.previousValue == nil)
        #expect(uncovered.delta == nil)
        #expect(uncovered.relativeDelta == nil)

        let idle = try #require(Self.tiles(dayCount: 7, samples: samples, previous: []).costPerMillionTokens)
        #expect(idle.previousValue == nil)

        let free = try #require(Self.tiles(
            dayCount: 7,
            samples: samples,
            previous: [Self.sample(day: -3, cost: 0, total: 1_000_000)]).costPerMillionTokens)
        #expect(free.previousValue == 0)
        #expect(free.delta == 4)
        #expect(free.relativeDelta == nil)
    }

    @Test
    func `model share delta follows the current top model`() throws {
        let tiles = Self.tiles(
            dayCount: 7,
            samples: [Self.sample(day: 0, cost: 10, models: [("codex:alpha", "alpha", 8), ("codex:beta", "beta", 2)])],
            previous: [Self.sample(
                day: -2,
                cost: 10,
                models: [("codex:alpha", "alpha", 3), ("codex:beta", "beta", 7)])])
        let share = try #require(tiles.topModelShare)
        #expect(share.modelName == "alpha")
        #expect(share.tile.value == 0.8)
        #expect(share.tile.previousValue == 0.3)
    }

    @Test
    func `plan value delta prorates the previous period the same way`() throws {
        let tile = try #require(Self.tiles(
            dayCount: 15,
            samples: [Self.sample(day: 0, cost: 300)],
            previous: [Self.sample(day: -15, cost: 150)],
            planMonthlyPrice: 200).planValue)
        #expect(tile.value == 3)
        #expect(tile.previousValue == 1.5)
        #expect(tile.delta == 1.5)
    }
}

// MARK: - Fixtures

extension SpendInsightTilesTests {
    private static let start = Date(timeIntervalSince1970: 1_782_864_000) // 2026-07-01 00:00:00 UTC

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func day(_ offset: Int) -> Date {
        self.calendar.date(byAdding: .day, value: offset, to: self.start)!
    }

    private static func tiles(
        dayCount: Int = 30,
        samples: [SpendInsightSample],
        previous: [SpendInsightSample]? = nil,
        planMonthlyPrice: Double? = nil) -> SpendInsightTiles
    {
        SpendInsightTiles(
            inputs: SpendInsightInputs(
                period: SpendInsightPeriod(start: self.start, dayCount: dayCount),
                samples: samples,
                previousSamples: previous),
            calendar: self.calendar,
            planMonthlyPrice: planMonthlyPrice)
    }

    private static func sample(
        source: String = "codex",
        day: Int = 0,
        cost: Double? = nil,
        input: Int? = nil,
        cacheRead: Int? = nil,
        cacheWrite: Int? = nil,
        output: Int? = nil,
        reasoning: Int? = nil,
        total: Int? = nil,
        models: [(id: String, name: String, cost: Double)] = []) -> SpendInsightSample
    {
        SpendInsightSample(
            sourceID: source,
            day: self.day(day),
            cost: cost,
            totalTokens: total,
            inputTokens: input,
            cacheReadTokens: cacheRead,
            cacheCreationTokens: cacheWrite,
            outputTokens: output,
            reasoningTokens: reasoning,
            modelCosts: models.map { SpendInsightSample.ModelCost(id: $0.id, name: $0.name, cost: $0.cost) })
    }
}
