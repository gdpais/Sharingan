import CodexBarCore
import Foundation

/// Burn Down for the card's chart slot: one quota window's remaining share against its ideal line.
struct MenuCardBurndownChart: Equatable {
    /// The plan usage series id (`name:windowMinutes`) the chart was built from.
    let seriesID: String
    let title: String
    let model: QuotaBurndownModel
}

/// Plan fit for the card's chart slot: each window's peak, capped windows marked, with the plain-rule verdict.
struct MenuCardPlanFitChart: Equatable {
    struct Bar: Identifiable, Equatable {
        let id: Int
        /// Slot position; the current window sits in the last slot.
        let x: Double
        let peakPercent: Double
        let isCapped: Bool
        let isCurrent: Bool
    }

    let seriesID: String
    let title: String
    let summary: PlanFit.Summary
    let bars: [Bar]
    let slotCount: Int
    let cappedSlot: ChartPalette.Slot

    var xDomain: ClosedRange<Double> {
        -0.5...(Double(self.slotCount) - 0.5)
    }
}

/// Builds the card's Burn Down and Plan fit charts from the provider's own plan usage history.
///
/// Both use the plan usage series the provider records, preferring the weekly window, so any provider with
/// history gets them. A provider without usable history gets nil, and its chart slot stays empty.
enum MenuCardInsightChartBuilder {
    /// The plan usage chart shows at most this many periods; Plan fit summarizes the same span.
    static let planFitMaxWindows = 30
    private static let burndownSeriesNames: [PlanUtilizationSeriesName] = [.session, .weekly, .monthly, .opus]

    static func burndown(
        provider: UsageProvider,
        histories: [PlanUtilizationSeriesHistory],
        workDays: Int?,
        now: Date) -> MenuCardBurndownChart?
    {
        let series = PlanUtilizationHistoryChartMenuView.visibleSeries(
            histories: histories,
            provider: provider,
            snapshot: nil).filter { self.burndownSeriesNames.contains($0.history.name) }
        for candidate in self.preferringWeekly(series) {
            guard let model = self.burndownModel(
                provider: provider,
                history: candidate.history,
                workDays: workDays,
                now: now)
            else { continue }
            return MenuCardBurndownChart(
                seriesID: candidate.id,
                title: "\(L("Burn Down")) · \(candidate.title)",
                model: model)
        }
        return nil
    }

    static func planFit(
        provider: UsageProvider,
        histories: [PlanUtilizationSeriesHistory],
        snapshot: UsageSnapshot?,
        now: Date) -> MenuCardPlanFitChart?
    {
        let series = PlanUtilizationHistoryChartMenuView.visibleSeries(
            histories: histories,
            provider: provider,
            snapshot: snapshot).filter { $0.history.windowMinutes > 0 && !$0.history.name.isQuotaObservation }
        for candidate in self.preferringWeekly(series) {
            let windowMinutes = candidate.history.windowMinutes
            let entries = candidate.history.entries.map { entry in
                PlanFit.HistoryEntry(
                    capturedAt: entry.capturedAt,
                    usedPercent: entry.usedPercent,
                    resetsAt: entry.resetsAt)
            }
            guard let grouping = PlanFit.windowGrouping(
                entries: entries,
                windowMinutes: windowMinutes,
                now: now,
                maxWindows: self.planFitMaxWindows),
                !grouping.windows.isEmpty
            else { continue }
            let summary = PlanFit.summary(windows: grouping.windows, windowMinutes: windowMinutes, now: now)
            let periods = grouping.windows.map { grouping.periodsBeforeCurrent($0.resetsAt) }
            let slotCount = max((periods.max() ?? 0) + 1, PlanFitChartLayout.minimumSlots)
            let bars = zip(summary.windows, periods).enumerated().map { index, pair in
                MenuCardPlanFitChart.Bar(
                    id: index,
                    x: Double(slotCount - 1 - pair.1),
                    peakPercent: pair.0.peakPercent,
                    isCapped: pair.0.isCapped,
                    isCurrent: pair.0.isCurrent)
            }
            return MenuCardPlanFitChart(
                seriesID: candidate.id,
                title: "\(L("Plan fit")) · \(candidate.title)",
                summary: summary,
                bars: bars,
                slotCount: slotCount,
                cappedSlot: PlanFitPresentation.cappedSlot(accent: ProviderAccentPalette.color(for: provider)))
        }
        return nil
    }

    /// The same window resolution the Burn Down submenu uses, for the newest capture of one series.
    static func burndownModel(
        provider: UsageProvider,
        history: PlanUtilizationSeriesHistory,
        workDays: Int?,
        now: Date) -> QuotaBurndownModel?
    {
        guard let latest = history.entries.last,
              let reset = latest.resetsAt,
              latest.capturedAt <= now,
              reset > now
        else { return nil }
        let window = ProviderDescriptorRegistry.descriptor(for: provider).pace.resolvedResetWindowForPace(
            RateWindow(
                usedPercent: latest.usedPercent,
                windowMinutes: history.windowMinutes,
                resetsAt: reset,
                resetDescription: nil))
        return QuotaBurndownModel(history: history, window: window, now: latest.capturedAt, workDays: workDays)
    }

    private static func preferringWeekly(
        _ series: [PlanUtilizationHistoryChartMenuView.VisibleSeries])
        -> [PlanUtilizationHistoryChartMenuView.VisibleSeries]
    {
        series.filter { $0.history.name == .weekly } + series.filter { $0.history.name != .weekly }
    }
}
