import Foundation

/// Plan prices for the plan value tile, each scoped to the sources whose spend its plan covers.
///
/// Plan value compares a provider's API-equivalent spend with that provider's plan price, so only the
/// spend of sources billed by a priced plan enters the comparison, against the sum of those plans' prices.
public struct SpendInsightPlanPricing: Sendable, Equatable {
    public struct Plan: Sendable, Equatable {
        /// Stable plan key, such as the provider's raw value.
        public let id: String
        /// Display name for the plan's scope, such as the provider's name.
        public let name: String
        /// Monthly price in the tiles' currency.
        public let monthlyPrice: Double
        /// Sources billed by this plan; `nil` covers every source.
        public let sourceIDs: Set<String>?

        public init(id: String, name: String, monthlyPrice: Double, sourceIDs: Set<String>?) {
            self.id = id
            self.name = name
            self.monthlyPrice = monthlyPrice
            self.sourceIDs = sourceIDs
        }

        func covers(_ sourceID: String) -> Bool {
            self.sourceIDs?.contains(sourceID) ?? true
        }
    }

    /// A user-entered price before scoping: in its own currency, keyed by plan.
    public struct Price: Sendable, Equatable {
        public let planID: String
        public let name: String
        public let monthlyPrice: Double
        public let currencyCode: String

        public init(planID: String, name: String, monthlyPrice: Double, currencyCode: String) {
            self.planID = planID
            self.name = name
            self.monthlyPrice = monthlyPrice
            self.currencyCode = currencyCode
        }
    }

    /// Plans with a usable price, in input order, one per id.
    public let plans: [Plan]

    public init(plans: [Plan]) {
        var seen = Set<String>()
        self.plans = plans.filter { plan in
            // Converted prices can exceed the editor's input ceiling, so only positivity is checked here.
            guard plan.monthlyPrice.isFinite, plan.monthlyPrice > 0,
                  plan.sourceIDs?.isEmpty != true,
                  !seen.contains(plan.id)
            else { return false }
            seen.insert(plan.id)
            return true
        }
    }

    /// One price for every source, the shape a single plan price setting had before prices were scoped.
    public static func unscoped(monthlyPrice: Double) -> SpendInsightPlanPricing {
        SpendInsightPlanPricing(plans: [Plan(id: "all", name: "", monthlyPrice: monthlyPrice, sourceIDs: nil)])
    }

    /// Scopes `prices` to the sources present in one currency group.
    ///
    /// - Parameters:
    ///   - sourcePlans: The plan each source of the group bills against (source ID to plan ID).
    ///   - currencyCode: The group's currency.
    ///   - convert: Converts an amount from one currency code to another; `nil` when no rate is known.
    ///     A price that cannot be converted stays out rather than being compared in the wrong currency.
    public static func scoped(
        prices: [Price],
        sourcePlans: [String: String],
        currencyCode: String,
        convert: (Double, String, String) -> Double?) -> SpendInsightPlanPricing
    {
        let plans = prices.compactMap { price -> Plan? in
            let sources = Set(sourcePlans.filter { $0.value == price.planID }.map(\.key))
            guard !sources.isEmpty, let amount = ProviderSpendPlan.validAmount(price.monthlyPrice) else { return nil }
            let converted: Double? = if price.currencyCode == currencyCode {
                amount
            } else {
                convert(amount, price.currencyCode, currencyCode)
            }
            guard let converted else { return nil }
            return Plan(id: price.planID, name: price.name, monthlyPrice: converted, sourceIDs: sources)
        }
        return SpendInsightPlanPricing(plans: plans)
    }

    public var isEmpty: Bool {
        self.plans.isEmpty
    }

    /// Sum of the plans' monthly prices.
    public var monthlyPrice: Double {
        self.plans.reduce(0) { $0 + $1.monthlyPrice }
    }

    func covers(_ sourceID: String) -> Bool {
        self.plans.contains { $0.covers(sourceID) }
    }
}
