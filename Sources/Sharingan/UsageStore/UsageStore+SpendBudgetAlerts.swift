import SharinganCore
import Foundation

/// Notification copy for a budget threshold, kept apart from posting so it can be tested.
enum SpendBudgetNotificationLogic {
    static func notificationIDPrefix(provider: UsageProvider, status: SpendBudgetStatus, percent: Int) -> String {
        "spend-budget-\(provider.rawValue)-\(status.month.key)-\(percent)"
    }

    static func notificationCopy(
        providerName: String,
        status: SpendBudgetStatus,
        percent: Int,
        currencyCode: String) -> (title: String, body: String)
    {
        let title = percent >= 100
            ? L("budget_notification_title_reached", providerName)
            : L("budget_notification_title_warning", providerName, spendInsightPercentText(Double(percent) / 100))
        let body = L(
            "budget_notification_body",
            UsageFormatter.currencyString(status.monthToDateCost, currencyCode: currencyCode),
            UsageFormatter.currencyString(status.budget, currencyCode: currencyCode))
        return (title, body)
    }
}

@MainActor
extension UsageStore {
    /// The cost history the budget is measured on: the same snapshot the cost history submenu draws.
    func spendBudgetTokenSnapshot(for provider: UsageProvider) -> CostUsageTokenSnapshot? {
        guard ProviderDescriptorRegistry.descriptor(for: provider).tokenCost.supportsTokenCost else { return nil }
        let projected = self.tokenSnapshot(
            fromProviderSnapshot: self.snapshot(for: provider.instanceID),
            provider: provider)
        if Self.tokenCostRequiresProviderSnapshot(provider) {
            return projected
        }
        return projected ?? self.tokenSnapshot(for: provider)
    }

    /// Month-to-date status for a provider's budget, in the budget's currency; `nil` without a budget,
    /// cost history, or an exchange rate between the two currencies.
    func spendBudgetStatus(
        for provider: UsageProvider,
        now: Date = Date()) -> (status: SpendBudgetStatus, currencyCode: String, sourceToBudget: Double)?
    {
        guard let plan = self.settings.spendPlan(for: provider),
              let budget = plan.validMonthlyBudget,
              let snapshot = self.spendBudgetTokenSnapshot(for: provider)
        else { return nil }
        let currencyCode = plan.resolvedCurrencyCode(fallback: snapshot.currencyCode)
        guard let sourceToBudget = CurrencyExchange.shared.convert(
            amount: 1,
            from: snapshot.currencyCode,
            to: currencyCode),
            let status = SpendBudgetStatus.make(
                snapshot: snapshot,
                budget: budget,
                now: now,
                calendar: self.settings.costUsageBucketCalendar,
                costMultiplier: sourceToBudget)
        else { return nil }
        return (status, currencyCode, sourceToBudget)
    }

    /// The budget as the cost history chart draws it, in the chart's display currency; `nil` without one.
    func costHistoryBudget(
        for provider: UsageProvider,
        displayCurrencyCode: String,
        sourceToDisplay: Double) -> CostHistoryBudget?
    {
        guard let resolved = self.spendBudgetStatus(for: provider) else { return nil }
        return CostHistoryBudget(
            status: resolved.status,
            sourceToBudget: resolved.sourceToBudget,
            displayCurrencyCode: displayCurrencyCode,
            sourceToDisplay: sourceToDisplay)
    }

    /// Announces each budget threshold once per calendar month, after a new cost snapshot is published.
    /// The notification and the `budget_reached` hook are independent: either can be off.
    func evaluateSpendBudgetAlerts(for provider: UsageProvider, now: Date = Date()) {
        guard let resolved = self.spendBudgetStatus(for: provider, now: now) else { return }
        let previous = self.settings.spendBudgetAlertState(for: provider)
        let evaluation = SpendBudgetAlerts.evaluate(
            status: resolved.status,
            currencyCode: resolved.currencyCode,
            previous: previous)
        // Recorded even while both channels are off, so turning one on later does not replay old crossings.
        self.settings.setSpendBudgetAlertState(evaluation.state, for: provider)
        guard let percent = evaluation.announcedPercent else { return }

        if self.settings.spendBudgetNotificationsEnabled {
            let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
            let copy = SpendBudgetNotificationLogic.notificationCopy(
                providerName: providerName,
                status: resolved.status,
                percent: percent,
                currencyCode: resolved.currencyCode)
            AppNotifications.shared.post(
                idPrefix: SpendBudgetNotificationLogic.notificationIDPrefix(
                    provider: provider,
                    status: resolved.status,
                    percent: percent),
                title: copy.title,
                body: copy.body,
                soundEnabled: self.settings.quotaWarningSoundEnabled)
        }
        self.dispatchSpendBudgetHook(
            HookEvent.budgetReached(
                provider: provider.rawValue,
                status: resolved.status,
                threshold: Double(percent) / 100,
                currencyCode: resolved.currencyCode,
                timestamp: now))
    }

    /// Runs the budget hook rules from this app's preferences, behind the shared hooks switch.
    private func dispatchSpendBudgetHook(_ event: HookEvent) {
        guard self.settings.config.hooks?.enabled == true else { return }
        let rules = self.settings.spendBudgetHookRules.filter { $0.matches(event) }
        guard !rules.isEmpty else { return }
        let config = HooksConfig(enabled: true, events: rules)
        let limiter = self.hookRateLimiter
        let environment = self.environmentBase
        Task.detached(priority: .utility) {
            await HookRunner.dispatch(
                event: event,
                config: config,
                rateLimiter: limiter,
                baseEnvironment: environment)
        }
    }
}
