import CoreGraphics
import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

struct SpendInsightTilesRowTests {
    @Test
    func `dashboard groups carry the previous period only when history covers it`() throws {
        let covered = try #require(Self.group(historyDays: 30))
        #expect(covered.insightInputs.period == SpendInsightPeriod(start: Self.day("2026-07-10"), dayCount: 7))
        #expect(covered.insightInputs.samples.map(\.day) == [Self.day("2026-07-16")])
        #expect(covered.insightInputs.samples.first?.cost == 2)
        #expect(covered.insightInputs.samples.first?.costCoversTokens == true)
        #expect(covered.insightInputs.previousSamples?.map(\.day) == [Self.day("2026-07-08")])

        let tiles = SpendInsightTiles(inputs: covered.insightInputs, calendar: covered.calendar, planMonthlyPrice: nil)
        let cost = try #require(tiles.costPerMillionTokens)
        #expect(cost.value == 2)
        #expect(cost.previousValue == 1)
        let share = try #require(tiles.topModelShare)
        #expect(share.modelID == "claude:test-model")
        #expect(share.tile.value == 1)

        // Seven days of history cannot cover the seven days before the range.
        let short = try #require(Self.group(historyDays: 7))
        #expect(short.insightInputs.samples.count == 1)
        #expect(short.insightInputs.previousSamples == nil)
    }

    @Test
    func `menu builds skip the insight tile inputs`() throws {
        let menu = try #require(Self.group(historyDays: 30, includesInsightTiles: false))
        #expect(menu.insightInputs == SpendInsightInputs())
        #expect(menu.totalCost == 2)
    }

    @Test
    func `days with unpriced tokens stay out of cost per million tokens`() throws {
        let partlyPriced = CostUsageDailyReport.Entry(
            date: "2026-07-16",
            inputTokens: 2_000_000,
            outputTokens: 0,
            totalTokens: 2_000_000,
            costUSD: 2,
            modelsUsed: ["test-model", "unpriced-model"],
            modelBreakdowns: [
                .init(modelName: "test-model", costUSD: 2, totalTokens: 1_000_000),
                .init(modelName: "unpriced-model", costUSD: nil, totalTokens: 1_000_000),
            ])
        let group = try #require(Self.group(historyDays: 30, daily: [partlyPriced]))
        #expect(group.insightInputs.samples.map(\.costCoversTokens) == [false])

        let tiles = SpendInsightTiles(inputs: group.insightInputs, calendar: group.calendar, planMonthlyPrice: nil)
        #expect(tiles.apiEquivalentCost == 2)
        #expect(tiles.costPerMillionTokens == nil)
    }

    @Test
    func `plan value shows a price hint until a plan price is set`() {
        let tiles = { (price: Double?) in
            SpendInsightTiles(
                inputs: SpendInsightInputs(
                    period: SpendInsightPeriod(start: Self.day("2026-07-01"), dayCount: 30),
                    samples: [SpendInsightSample(sourceID: "claude", day: Self.day("2026-07-02"), cost: 1300)]),
                calendar: Self.calendar,
                planMonthlyPrice: price)
        }
        SharinganLocalizationOverride.$appLanguage.withValue("en") {
            let hint = SpendInsightTileItem.items(for: tiles(nil), currencyCode: "USD", planMonthlyPrice: nil)
            #expect(hint.map(\.kind) == [.planValue])
            #expect(hint.first?.value == nil)
            #expect(hint.first?.detail == "Set a plan price to compare")

            let priced = SpendInsightTileItem.items(for: tiles(200), currencyCode: "USD", planMonthlyPrice: 200)
            #expect(priced.first?.value == "6.5×")
            #expect(priced.first?.detail == "API-equivalent vs $200.00 plan")
            #expect(priced.first?.delta == nil)
        }

        let noSpend = SpendInsightTiles(inputs: SpendInsightInputs(), calendar: Self.calendar, planMonthlyPrice: nil)
        #expect(SpendInsightTileItem.items(for: noSpend, currencyCode: "USD", planMonthlyPrice: nil).isEmpty)
    }

    @Test
    func `delta text carries direction in arrows and drops them when the change rounds away`() {
        SharinganLocalizationOverride.$appLanguage.withValue("en") {
            #expect(spendInsightDeltaText(0.12, style: .relative) == "▲ 12% vs previous period")
            #expect(spendInsightDeltaText(-0.032, style: .points) == "▼ 3.2 pts vs previous period")
            #expect(spendInsightDeltaText(0.0001, style: .points) == "0 pts vs previous period")
            #expect(spendInsightDeltaText(0.8, style: .multiple) == "▲ 0.8× vs previous period")
            #expect(spendInsightDeltaText(nil, style: .relative) == nil)
            #expect(spendInsightDeltaText(Double.nan, style: .relative) == nil)
        }
    }

    @Test
    func `sparkline breaks at gaps and centers flat trends`() {
        let size = CGSize(width: 90, height: 20)
        let segments = SpendInsightSparklineGeometry.segments(values: [1, nil, 2, 3], size: size, inset: 0)
        #expect(segments == [[CGPoint(x: 0, y: 20)], [CGPoint(x: 60, y: 10), CGPoint(x: 90, y: 0)]])
        #expect(SpendInsightSparklineGeometry.dots(in: segments) == [CGPoint(x: 0, y: 20), CGPoint(x: 90, y: 0)])

        let flat = SpendInsightSparklineGeometry.segments(values: [5, 5], size: size, inset: 0)
        #expect(flat == [[CGPoint(x: 0, y: 10), CGPoint(x: 90, y: 10)]])
        #expect(SpendInsightSparklineGeometry.segments(values: [nil, nil], size: size).isEmpty)
    }
}

// MARK: - Fixtures

extension SpendInsightTilesRowTests {
    private static let now = Date(timeIntervalSince1970: 1_784_203_200) // 2026-07-16 12:00:00 UTC

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func day(_ value: String) -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        return self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private static func group(
        historyDays: Int,
        daily: [CostUsageDailyReport.Entry]? = nil,
        includesInsightTiles: Bool = true) -> SpendDashboardModel.CurrencyGroup?
    {
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            currencyCode: "USD",
            historyDays: historyDays,
            daily: daily ?? [Self.entry(day: "2026-07-16", cost: 2), Self.entry(day: "2026-07-08", cost: 1)],
            updatedAt: self.now)
        let input = SpendDashboardModel.ProviderInput(provider: .claude, displayName: "Claude", snapshot: snapshot)
        return SpendDashboardModel.build(
            inputs: [input],
            requestedDays: 7,
            now: self.now,
            calendar: self.calendar,
            includesInsightTiles: includesInsightTiles)
            .groups.first
    }

    private static func entry(day: String, cost: Double) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: 1_000_000,
            outputTokens: 0,
            totalTokens: 1_000_000,
            costUSD: cost,
            modelsUsed: ["test-model"],
            modelBreakdowns: [.init(modelName: "test-model", costUSD: cost, totalTokens: 1_000_000)])
    }
}
