import Foundation
import SharinganCore

/// Plan prices, monthly budgets and what reads them.
///
/// The amounts live in Sharingan's config as the provider key `spendPlan` (see `ProviderSpendPlan`).
/// Budget alert state stays in this app's defaults: it is per-Mac bookkeeping. `budget_reached` hook
/// rules are ordinary rules under `hooks.events`.
extension SettingsStore {
    private static let spendBudgetNotificationsEnabledKey = "spendBudgetNotificationsEnabled"
    private static let spendBudgetAlertStatesKey = "spendBudgetAlertStates"

    // MARK: - Amounts

    func spendPlan(for provider: UsageProvider) -> ProviderSpendPlan? {
        self.configSnapshot.providerConfig(for: provider.instanceID)?.spendPlan
    }

    /// Stores the plan, or removes it when it carries no usable amount. A display-only change: it never
    /// changes fetch identity or schedules a refresh.
    func setSpendPlan(_ plan: ProviderSpendPlan?, for provider: UsageProvider) {
        let normalized = plan?.isEmpty == false ? plan : nil
        guard self.spendPlan(for: provider) != normalized else { return }
        self.updateProviderConfig(provider: provider, affectsBackgroundWork: false) { entry in
            entry.spendPlan = normalized
        }
    }

    /// Every first-party provider with a plan price or budget.
    var spendPlansByProvider: [UsageProvider: ProviderSpendPlan] {
        var plans: [UsageProvider: ProviderSpendPlan] = [:]
        for entry in self.configSnapshot.providers {
            guard let provider = entry.id.firstPartyProvider, let plan = entry.spendPlan else { continue }
            plans[provider] = plan
        }
        return plans
    }

    var hasAnySpendBudget: Bool {
        self.spendPlansByProvider.values.contains { $0.validMonthlyBudget != nil }
    }

    // MARK: - Budget alerts

    /// On unless turned off. Budget alerts only fire for providers with a budget, and none has one by
    /// default, so this changes nothing until a budget is set.
    var spendBudgetNotificationsEnabled: Bool {
        get { self.userDefaults.object(forKey: Self.spendBudgetNotificationsEnabledKey) as? Bool ?? true }
        set { self.userDefaults.set(newValue, forKey: Self.spendBudgetNotificationsEnabledKey) }
    }

    func spendBudgetAlertState(for provider: UsageProvider) -> SpendBudgetAlertState? {
        self.spendBudgetAlertStates()[provider.rawValue]
    }

    func setSpendBudgetAlertState(_ state: SpendBudgetAlertState?, for provider: UsageProvider) {
        var states = self.spendBudgetAlertStates()
        guard states[provider.rawValue] != state else { return }
        states[provider.rawValue] = state
        if let data = try? JSONEncoder().encode(states) {
            self.userDefaults.set(data, forKey: Self.spendBudgetAlertStatesKey)
        }
    }

    private func spendBudgetAlertStates() -> [String: SpendBudgetAlertState] {
        guard let data = self.userDefaults.data(forKey: Self.spendBudgetAlertStatesKey),
              let states = try? JSONDecoder().decode([String: SpendBudgetAlertState].self, from: data)
        else { return [:] }
        return states
    }
}
