import SharinganCore
import SwiftUI

extension EnvironmentValues {
    /// Each provider's plan price and budget, injected by the Usage & Spend pane for the insight tiles.
    @Entry var spendPlans: [UsageProvider: ProviderSpendPlan] = [:]
}

extension SpendInsightTileItem {
    /// Plan prices for one currency group, each scoped to its own provider's sources.
    ///
    /// A provider takes part only when it has a plan price and spend in this group. Prices in another
    /// currency are converted at the app's exchange rates, or left out when no rate is known, so the
    /// comparison is always made in the group's currency.
    static func planPricing(
        group: SpendDashboardModel.CurrencyGroup,
        spendPlans: [UsageProvider: ProviderSpendPlan],
        convert: (Double, String, String) -> Double? = { amount, from, to in
            CurrencyExchange.shared.convert(amount: amount, from: from, to: to)
        }) -> SpendInsightPlanPricing
    {
        guard !spendPlans.isEmpty else { return SpendInsightPlanPricing(plans: []) }
        var sourcePlans: [String: String] = [:]
        var providers: [UsageProvider] = []
        for row in group.providers {
            sourcePlans[row.id] = row.provider.rawValue
            if !providers.contains(row.provider) {
                providers.append(row.provider)
            }
        }
        let prices = providers.compactMap { provider -> SpendInsightPlanPricing.Price? in
            guard let plan = spendPlans[provider], let price = plan.validPlanMonthlyPrice else { return nil }
            return SpendInsightPlanPricing.Price(
                planID: provider.rawValue,
                name: ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName,
                monthlyPrice: price,
                currencyCode: plan.resolvedCurrencyCode(fallback: group.currencyCode))
        }
        return SpendInsightPlanPricing.scoped(
            prices: prices,
            sourcePlans: sourcePlans,
            currencyCode: group.currencyCode,
            convert: convert)
    }

    /// The priced plans' names when the group also holds providers without a price, so the tile says
    /// whose spend it compares; `nil` when every provider in the group is priced.
    static func planScopeNames(
        pricing: SpendInsightPlanPricing,
        group: SpendDashboardModel.CurrencyGroup) -> [String]?
    {
        let pricedIDs = Set(pricing.plans.map(\.id))
        let groupIDs = Set(group.providers.map(\.provider.rawValue))
        guard !pricedIDs.isEmpty, !groupIDs.isSubset(of: pricedIDs) else { return nil }
        return pricing.plans.map(\.name)
    }
}
