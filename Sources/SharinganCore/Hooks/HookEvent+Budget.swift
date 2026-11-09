import Foundation

extension HookEvent {
    /// `budget_reached` for one provider's monthly budget. Amounts are in the budget's currency; the
    /// spend side is a local estimate, never a bill, which every field name says.
    public static func budgetReached(
        provider: String,
        status: SpendBudgetStatus,
        threshold: Double,
        currencyCode: String,
        timestamp: Date = Date()) -> HookEvent
    {
        let fraction = status.fraction
        return HookEvent(
            event: .budgetReached,
            provider: provider,
            window: "month",
            estimatedCost: status.monthToDateCost,
            budget: status.budget,
            estimatedBudgetFraction: fraction.isFinite ? fraction : nil,
            budgetThreshold: threshold,
            currency: currencyCode,
            budgetMonth: status.month.key,
            estimatedCostIsPartial: !status.isComplete,
            timestamp: timestamp)
    }

    /// The budget fields as `SHARINGAN_*` variables; empty for every other event.
    func budgetEnvironmentVariables() -> [String: String] {
        let fields: [(String, String?)] = [
            ("SHARINGAN_ESTIMATED_COST", self.estimatedCost.map(Self.number)),
            ("SHARINGAN_BUDGET", self.budget.map(Self.number)),
            ("SHARINGAN_ESTIMATED_BUDGET_FRACTION", self.estimatedBudgetFraction.map(Self.number)),
            ("SHARINGAN_BUDGET_THRESHOLD", self.budgetThreshold.map(Self.number)),
            ("SHARINGAN_CURRENCY", self.currency),
            ("SHARINGAN_BUDGET_MONTH", self.budgetMonth),
            ("SHARINGAN_ESTIMATED_COST_IS_PARTIAL", self.estimatedCostIsPartial.map { $0 ? "true" : "false" }),
        ]
        return Dictionary(uniqueKeysWithValues: fields.compactMap { key, value in value.map { (key, $0) } })
    }
}
