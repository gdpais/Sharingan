import Foundation
import SharinganCore

extension UsageStore {
    /// The provider's card layout for a menu card, with the Burn Down or Plan fit chart it picked.
    ///
    /// Nil for Settings previews, which keep every section, and for a default card. Charts are built only when
    /// chosen, from the card's own history: the live account's history for the live card, the account's
    /// recorded selection for an account card, and nothing otherwise, so a card never shows another account's
    /// or provider's data.
    func menuCardLayoutContext(
        for provider: UsageProvider,
        context: UsageMenuCardContext,
        now: Date = Date()) -> MenuCardLayoutContext?
    {
        guard !context.isSettings else { return nil }
        let layout = self.settings.menuCardLayout(for: provider)
        guard !layout.hasDefaultCard else { return nil }
        var result = MenuCardLayoutContext(layout: layout)
        switch layout.chart {
        case .burndown:
            result.burndown = self.menuCardBurndownChart(for: provider, context: context, now: now)
        case .planFit:
            result.planFit = self.menuCardPlanFitChart(for: provider, context: context, now: now)
        case .automatic, .live, .spend, .none:
            break
        }
        return result
    }

    /// What the provider's live menu card can show now; Settings flags the rest as unavailable.
    func menuCardLayoutAvailability(for provider: UsageProvider, now: Date = Date()) -> MenuCardLayoutAvailability {
        let model = UsageMenuCardView.Model.make(self.menuCardInput(for: provider, context: .menu, now: now))
            .applyingUsageItemVisibility(hiddenItemIDs: self.settings.hiddenUsageItemIDs(for: provider))
        return model.cardLayoutAvailability(
            burndown: self.menuCardBurndownChart(for: provider, context: .menu, now: now) != nil,
            planFit: self.menuCardPlanFitChart(for: provider, context: .menu, now: now) != nil)
    }

    func menuCardBurndownChart(
        for provider: UsageProvider,
        context: UsageMenuCardContext,
        now: Date) -> MenuCardBurndownChart?
    {
        let source = self.menuCardHistorySource(for: provider, context: context)
        return MenuCardInsightChartBuilder.burndown(
            provider: provider,
            histories: source.histories,
            workDays: self.settings.weeklyProgressWorkDays,
            now: now)
    }

    func menuCardPlanFitChart(
        for provider: UsageProvider,
        context: UsageMenuCardContext,
        now: Date) -> MenuCardPlanFitChart?
    {
        let source = self.menuCardHistorySource(for: provider, context: context)
        return MenuCardInsightChartBuilder.planFit(
            provider: provider,
            histories: source.histories,
            snapshot: source.snapshot,
            now: now)
    }

    private func menuCardHistorySource(
        for provider: UsageProvider,
        context: UsageMenuCardContext) -> (histories: [PlanUtilizationSeriesHistory], snapshot: UsageSnapshot?)
    {
        if let account = context.account {
            return (account.historySelection?.histories ?? [], account.snapshot)
        }
        // Read-only: building a menu card must never migrate or persist history.
        let selection = self.planUtilizationHistorySelection(for: provider, readOnly: true)
        return (selection.histories, self.snapshot(for: provider.instanceID))
    }
}
