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
        var env: [String: String] = [:]
        if let estimatedCost { env["SHARINGAN_ESTIMATED_COST"] = Self.number(estimatedCost) }
        if let budget { env["SHARINGAN_BUDGET"] = Self.number(budget) }
        if let estimatedBudgetFraction {
            env["SHARINGAN_ESTIMATED_BUDGET_FRACTION"] = Self.number(estimatedBudgetFraction)
        }
        if let budgetThreshold { env["SHARINGAN_BUDGET_THRESHOLD"] = Self.number(budgetThreshold) }
        if let currency { env["SHARINGAN_CURRENCY"] = currency }
        if let budgetMonth { env["SHARINGAN_BUDGET_MONTH"] = budgetMonth }
        if let estimatedCostIsPartial {
            env["SHARINGAN_ESTIMATED_COST_IS_PARTIAL"] = estimatedCostIsPartial ? "true" : "false"
        }
        return env
    }
}
