import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

struct SpendInsightPlanValueTests {
    @Test
    func `plan value compares only the priced provider's spend with its price`() throws {
        let pricing = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 200, sourceIDs: ["codex", "opencodex"]),
        ])
        let tiles = Self.tiles(
            samples: [
                Self.sample(source: "codex", day: 0, cost: 300),
                Self.sample(source: "opencodex", day: 1, cost: 100),
                Self.sample(source: "claude", day: 2, cost: 5000),
            ],
            pricing: pricing)
        #expect(try #require(tiles.planValue).value == 2)
        #expect(tiles.apiEquivalentCost == 5400)
    }

    @Test
    func `several priced plans sum their spend and their prices`() throws {
        let pricing = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 200, sourceIDs: ["codex"]),
            .init(id: "claude", name: "Claude", monthlyPrice: 100, sourceIDs: ["claude"]),
        ])
        let tiles = Self.tiles(
            samples: [
                Self.sample(source: "codex", day: 0, cost: 300),
                Self.sample(source: "claude", day: 3, cost: 150),
                Self.sample(source: "cursor", day: 4, cost: 999),
            ],
            pricing: pricing)
        #expect(try #require(tiles.planValue).value == 1.5)
        #expect(pricing.monthlyPrice == 300)
    }

    @Test
    func `no priced spend or no usable price hides plan value`() {
        let codexOnly = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 200, sourceIDs: ["codex"]),
        ])
        #expect(Self.tiles(samples: [Self.sample(source: "claude", day: 0, cost: 50)], pricing: codexOnly)
            .planValue == nil)
        let invalid = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 0, sourceIDs: ["codex"]),
            .init(id: "claude", name: "Claude", monthlyPrice: .nan, sourceIDs: ["claude"]),
            .init(id: "cursor", name: "Cursor", monthlyPrice: 20, sourceIDs: []),
        ])
        #expect(invalid.isEmpty)
        #expect(Self.tiles(samples: [Self.sample(source: "codex", day: 0, cost: 50)], pricing: invalid)
            .planValue == nil)
        #expect(Self.tiles(samples: [Self.sample(source: "codex", day: 0, cost: 50)], pricing: nil).planValue == nil)
    }

    /// A 30-day range whose history starts on day 20 holds 10 days of plan price, not 30.
    @Test
    func `a price is spread only over the days its sources' history covers`() throws {
        let pricing = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 300, sourceIDs: ["codex"]),
        ])
        let tile = try #require(Self.tiles(
            samples: [Self.sample(source: "codex", day: 25, cost: 100)],
            coverage: ["codex": Self.day(20)...Self.day(29)],
            pricing: pricing).planValue)
        #expect(abs(tile.value - 1) < 1e-12)
        #expect(tile.trend.count == 12)
        #expect(tile.trend[0...7].allSatisfy { $0 == nil })
        // Bucket 10 holds days 25 to 27: $100 against three days of a $300 month.
        #expect(abs((tile.trend[10] ?? 0) - 100.0 / 30.0) < 1e-12)

        let unscoped = try #require(Self.tiles(
            samples: [Self.sample(source: "codex", day: 25, cost: 100)],
            pricing: pricing).planValue)
        #expect(abs(unscoped.value - 1.0 / 3.0) < 1e-12)
    }

    @Test
    func `a priced provider without history in the range adds no price`() throws {
        let pricing = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 200, sourceIDs: ["codex"]),
            .init(id: "claude", name: "Claude", monthlyPrice: 100, sourceIDs: ["claude"]),
        ])
        let tile = try #require(Self.tiles(
            samples: [Self.sample(source: "codex", day: 2, cost: 400)],
            coverage: ["codex": Self.day(0)...Self.day(29)],
            pricing: pricing).planValue)
        #expect(tile.value == 2)
    }

    @Test
    func `the previous period compares priced spend over its whole length`() throws {
        let pricing = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 200, sourceIDs: ["codex"]),
        ])
        let tile = try #require(Self.tiles(
            dayCount: 15,
            samples: [Self.sample(source: "codex", day: 0, cost: 300)],
            previous: [
                Self.sample(source: "codex", day: -15, cost: 150),
                Self.sample(source: "claude", day: -14, cost: 900),
            ],
            pricing: pricing).planValue)
        #expect(tile.value == 3)
        #expect(tile.previousValue == 1.5)
    }

    @Test
    func `scoped prices convert into the group's currency or stay out`() {
        let pricing = SpendInsightPlanPricing.scoped(
            prices: [
                .init(planID: "codex", name: "Codex", monthlyPrice: 20, currencyCode: "USD"),
                .init(planID: "claude", name: "Claude", monthlyPrice: 100, currencyCode: "EUR"),
                .init(planID: "cursor", name: "Cursor", monthlyPrice: 40, currencyCode: "XYZ"),
                .init(planID: "gemini", name: "Gemini", monthlyPrice: 20, currencyCode: "USD"),
            ],
            sourcePlans: ["codex": "codex", "opencodex": "codex", "claude": "claude", "cursor": "cursor"],
            currencyCode: "USD",
            convert: { amount, from, to in from == "EUR" && to == "USD" ? amount * 1.1 : nil })
        #expect(pricing.plans.map(\.id) == ["codex", "claude"])
        #expect(pricing.plans.first?.sourceIDs == ["codex", "opencodex"])
        #expect(abs(pricing.monthlyPrice - 130) < 1e-9)
    }

    // MARK: - Dashboard groups

    @Test
    func `group pricing follows each provider's own sources and names a partial scope`() {
        let group = Self.group(rows: [("codex", .codex), ("opencodex", .codex), ("claude", .claude)])
        let codexOnly = SpendInsightTileItem.planPricing(
            group: group,
            spendPlans: [
                .codex: ProviderSpendPlan(planMonthlyPrice: 20, currencyCode: "USD"),
                .gemini: ProviderSpendPlan(planMonthlyPrice: 20, currencyCode: "USD"),
                .claude: ProviderSpendPlan(monthlyBudget: 100, currencyCode: "USD"),
            ],
            convert: { _, _, _ in nil })
        #expect(codexOnly.plans.map(\.id) == ["codex"])
        #expect(codexOnly.plans.first?.sourceIDs == ["codex", "opencodex"])
        #expect(SpendInsightTileItem.planScopeNames(pricing: codexOnly, group: group)
            == [ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName])

        let both = SpendInsightTileItem.planPricing(
            group: group,
            spendPlans: [
                .codex: ProviderSpendPlan(planMonthlyPrice: 20, currencyCode: "USD"),
                .claude: ProviderSpendPlan(planMonthlyPrice: 100),
            ],
            convert: { _, _, _ in nil })
        #expect(both.plans.count == 2)
        #expect(SpendInsightTileItem.planScopeNames(pricing: both, group: group) == nil)
        #expect(SpendInsightTileItem.planPricing(group: group, spendPlans: [:]).isEmpty)
    }

    @Test
    func `the plan value tile names its scope and its prices`() throws {
        let pricing = SpendInsightPlanPricing(plans: [
            .init(id: "codex", name: "Codex", monthlyPrice: 200, sourceIDs: ["codex"]),
            .init(id: "claude", name: "Claude", monthlyPrice: 100, sourceIDs: ["claude"]),
        ])
        let tiles = Self.tiles(samples: [Self.sample(source: "codex", day: 0, cost: 600)], pricing: pricing)
        let items = SharinganLocalizationOverride.$appLanguage.withValue("en") {
            SpendInsightTileItem.items(
                for: tiles,
                currencyCode: "USD",
                planPricing: pricing,
                planScopeNames: ["Codex", "Claude"])
        }
        let item = try #require(items.first { $0.kind == .planValue })
        #expect(item.title == "Plan value · Codex, Claude")
        #expect(item.value == "2×")
        #expect(item.detail == "API-equivalent vs $300.00 in plans")

        let hidden = SpendInsightTileItem.items(for: tiles, currencyCode: "USD", planPricing: nil)
        #expect(!hidden.contains { $0.kind == .planValue })
    }
}

// MARK: - Fixtures

extension SpendInsightPlanValueTests {
    private static let start = Date(timeIntervalSince1970: 1_782_864_000) // 2026-07-01 00:00:00 UTC

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func day(_ offset: Int) -> Date {
        self.calendar.date(byAdding: .day, value: offset, to: self.start)!
    }

    private static func sample(source: String, day: Int, cost: Double?) -> SpendInsightSample {
        SpendInsightSample(sourceID: source, day: self.day(day), cost: cost)
    }

    private static func tiles(
        dayCount: Int = 30,
        samples: [SpendInsightSample],
        previous: [SpendInsightSample]? = nil,
        coverage: [String: ClosedRange<Date>] = [:],
        pricing: SpendInsightPlanPricing?) -> SpendInsightTiles
    {
        SpendInsightTiles(
            inputs: SpendInsightInputs(
                period: SpendInsightPeriod(start: self.start, dayCount: dayCount),
                samples: samples,
                previousSamples: previous,
                coverage: coverage),
            calendar: self.calendar,
            planPricing: pricing)
    }

    private static func group(rows: [(id: String, provider: UsageProvider)]) -> SpendDashboardModel.CurrencyGroup {
        SpendDashboardModel.CurrencyGroup(
            currencyCode: "USD",
            providers: rows.enumerated().map { index, row in
                SpendDashboardModel.ProviderRow(
                    id: row.id,
                    rank: index + 1,
                    provider: row.provider,
                    displayName: row.id,
                    totalTokens: nil,
                    totalCost: nil,
                    coveredDayCount: 0)
            },
            models: [],
            dailyPoints: [],
            totalTokens: nil,
            totalCost: nil,
            coveredDayCount: 0,
            chartDomain: Date.distantPast...Date.distantPast,
            modelHistoryCompleteness: .incomplete,
            timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}
