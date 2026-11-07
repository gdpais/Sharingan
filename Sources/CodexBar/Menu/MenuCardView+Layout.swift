import CodexBarCore
import SwiftUI

// MARK: - Presentation

/// A provider's card layout as applied to one built menu card model.
///
/// `standard` means no layout was applied, which is today's card. Hiding a section or picking a chart is applied
/// to the model's own fields, so every surface that draws the model (single card, split menu rows, Overview)
/// follows it and the height fingerprint changes with it.
struct MenuCardLayoutPresentation {
    /// Nil for today's card.
    var resolved: MenuCardResolvedLayout?
    /// Burn Down or Plan fit data for the chart slot, set only when that chart was chosen and has data.
    var insightChart: MenuCardInsightChart?
    /// The built-in arrangement cannot draw this layout (for example a spend chart without its cost summary).
    var requiresArrangedRendering = false

    static let standard = MenuCardLayoutPresentation()

    /// Reorderable sections to draw one after another, or nil to keep the built-in arrangement.
    var arrangedOrder: [MenuCardSectionKind]? {
        guard let resolved, !resolved.usesDefaultOrder || self.requiresArrangedRendering else { return nil }
        return resolved.sections.filter(\.isReorderable)
    }

    var heightFingerprint: String {
        guard let resolved else { return "standard" }
        return [
            "sections:\(resolved.sections.map(\.rawValue).joined(separator: ","))",
            "chart:\(resolved.chart.rawValue)",
            self.arrangedOrder == nil ? "built-in" : "arranged",
            "insight:\(self.insightChart?.heightFingerprint ?? "nil")",
        ].joined(separator: ";")
    }
}

/// Burn Down or Plan fit content for the card's chart slot.
enum MenuCardInsightChart {
    case burndown(MenuCardBurndownChart)
    case planFit(MenuCardPlanFitChart)

    var heightFingerprint: String {
        switch self {
        case let .burndown(chart): "burndown:\(chart.seriesID)"
        case let .planFit(chart): "planFit:\(chart.seriesID)"
        }
    }
}

/// What `applyingCardLayout` needs beyond the model: the stored layout and the provider's own insight charts.
struct MenuCardLayoutContext {
    let layout: MenuCardLayout
    var burndown: MenuCardBurndownChart?
    var planFit: MenuCardPlanFitChart?
}

// MARK: - Projection

extension UsageMenuCardView.Model {
    /// The sections and charts this model has data for. Burn Down and Plan fit come from history, not the model.
    func cardLayoutAvailability(burndown: Bool, planFit: Bool) -> MenuCardLayoutAvailability {
        var sections: Set<MenuCardSectionKind> = []
        if self.hasCardUsageRows { sections.insert(.usage) }
        if self.hasCardPaceDetails { sections.insert(.pace) }
        if self.creditsText != nil { sections.insert(.credits) }
        if self.providerCost != nil { sections.insert(.extraUsage) }
        if self.inlineUsageDashboard?.hasNonChartContent == true || self.tokenUsage != nil {
            sections.insert(.cost)
        }
        var charts: Set<MenuCardChartChoice> = []
        if self.throughput != nil { charts.insert(.live) }
        if self.inlineUsageDashboard?.points.isEmpty == false { charts.insert(.spend) }
        if burndown { charts.insert(.burndown) }
        if planFit { charts.insert(.planFit) }
        if !charts.isEmpty { sections.insert(.chart) }
        return MenuCardLayoutAvailability(sections: sections, charts: charts)
    }

    /// The model with the provider's card layout applied. Nil or a default card returns the model unchanged.
    func applyingCardLayout(_ context: MenuCardLayoutContext?) -> Self {
        guard let context, !context.layout.hasDefaultCard else { return self }
        let layout = context.layout
        let resolved = layout.resolved(for: self.cardLayoutAvailability(
            burndown: context.burndown != nil,
            planFit: context.planFit != nil))
        var projected = self
        if !layout.isVisible(.usage) { projected.hideCardUsageRows() }
        if !layout.isVisible(.pace) { projected.hideCardPace() }
        if !layout.isVisible(.credits) { projected.hideCardCredits() }
        if !layout.isVisible(.extraUsage) { projected.providerCost = nil }

        var insightChart: MenuCardInsightChart?
        switch resolved.chart {
        case .automatic:
            break
        case .live:
            projected.dropCardSpendPoints()
        case .spend:
            projected.throughput = nil
        case .burndown:
            projected.throughput = nil
            projected.dropCardSpendPoints()
            insightChart = context.burndown.map { MenuCardInsightChart.burndown($0) }
        case .planFit:
            projected.throughput = nil
            projected.dropCardSpendPoints()
            insightChart = context.planFit.map { MenuCardInsightChart.planFit($0) }
        case .none:
            projected.throughput = nil
            projected.dropCardSpendPoints()
        }

        var requiresArrangedRendering = false
        if !layout.isVisible(.cost) {
            projected.tokenUsage = nil
            if let dashboard = projected.inlineUsageDashboard, !dashboard.points.isEmpty {
                // The spend chart still draws from the dashboard; only its summary rows go.
                projected.inlineUsageDashboard = dashboard.replacingContent(points: dashboard.points)
                requiresArrangedRendering = true
            } else {
                projected.inlineUsageDashboard = nil
            }
        }
        projected.cardLayout = MenuCardLayoutPresentation(
            resolved: resolved,
            insightChart: insightChart,
            requiresArrangedRendering: requiresArrangedRendering)
        return projected
    }

    private var hasCardUsageRows: Bool {
        !self.metrics.isEmpty ||
            !self.usageNotes.isEmpty ||
            !self.subscriptionNotes.isEmpty ||
            !self.providerDetails.isEmpty ||
            self.limitResetCredits != nil ||
            self.cloudCredits != nil ||
            self.placeholder != nil
    }

    private var hasCardPaceDetails: Bool {
        self.providerCost?.dailyTargetText != nil || self.metrics.contains { metric in
            metric.pacePercent != nil || metric.detailIsPaceDerived ||
                metric.sessionEquivalentDetail != nil || metric.dailyTargetText != nil
        }
    }

    private mutating func hideCardUsageRows() {
        self.metrics = []
        self.usageNotes = []
        self.subscriptionNotes = []
        self.providerDetails = []
        self.providerDetailRawTitles = []
        self.limitResetCredits = nil
        self.cloudCredits = nil
        self.placeholder = nil
        self.openAIAPIUsage = nil
    }

    /// Matches a card built with pace turned off: no pace text, markers, session equivalents or daily targets.
    private mutating func hideCardPace() {
        self.metrics = Self.paceGatedMetrics(self.metrics, paceVisible: false).map { metric in
            var result = metric
            result.dailyTargetText = nil
            return result
        }
        self.providerCost?.dailyTargetText = nil
        self.detailPaceVisible = false
    }

    private mutating func hideCardCredits() {
        self.creditsText = nil
        self.creditsRemaining = nil
        self.creditsProgressPercent = nil
        self.creditsScaleText = nil
        self.creditsHintText = nil
        self.creditsHintCopyText = nil
    }

    /// Removes the spend bars and keeps the cost summary; a dashboard with nothing else left goes away.
    private mutating func dropCardSpendPoints() {
        guard let dashboard = self.inlineUsageDashboard, !dashboard.points.isEmpty else { return }
        let summary = dashboard.replacingContent(
            points: [],
            kpis: dashboard.kpis,
            quotaWindows: dashboard.quotaWindows,
            detailLines: dashboard.detailLines)
        self.inlineUsageDashboard = summary.hasNonChartContent ? summary : nil
    }
}

extension InlineUsageDashboardModel {
    /// KPIs, recent windows or detail lines: everything the dashboard draws besides its spend bars.
    var hasNonChartContent: Bool {
        !self.kpis.isEmpty || !self.quotaWindows.isEmpty || !self.detailLines.isEmpty
    }

    func replacingContent(
        points: [Point],
        kpis: [KPI] = [],
        quotaWindows: [QuotaWindow] = [],
        detailLines: [String] = []) -> InlineUsageDashboardModel
    {
        var model = InlineUsageDashboardModel(
            accessibilityLabel: self.accessibilityLabel,
            valueStyle: self.valueStyle,
            kpis: kpis,
            points: points,
            detailLines: detailLines)
        model.quotaWindows = quotaWindows
        model.barColor = self.barColor
        model.currencyCode = self.currencyCode
        model.chartTitle = self.chartTitle
        return model
    }
}

// MARK: - Arrangement

/// Pure rules for drawing a card section by section in the layout's order.
enum MenuCardArrangement {
    /// Kinds in `order` that have something to draw. Split menus draw credits, extra usage and the cost
    /// section as their own menu rows, so their usage row passes `includesStandaloneSections: false`.
    static func blocks(
        for model: UsageMenuCardView.Model,
        order: [MenuCardSectionKind],
        includesStandaloneSections: Bool) -> [MenuCardSectionKind]
    {
        order.filter { kind in
            self.hasContent(kind, model: model, includesStandaloneSections: includesStandaloneSections)
        }
    }

    static func hasContent(
        _ kind: MenuCardSectionKind,
        model: UsageMenuCardView.Model,
        includesStandaloneSections: Bool) -> Bool
    {
        switch kind {
        case .usage:
            self.usageRowsModel(model).hasCardUsageBlock
        case .pace:
            false
        case .chart:
            model.throughput != nil || model.cardLayout.insightChart != nil ||
                model.inlineUsageDashboard?.points.isEmpty == false
        case .credits:
            includesStandaloneSections && model.creditsText != nil
        case .extraUsage:
            includesStandaloneSections && model.providerCost != nil
        case .cost:
            model.inlineUsageDashboard?.hasNonChartContent == true ||
                (includesStandaloneSections && model.tokenUsage != nil)
        }
    }

    /// Usage rows and the chart read as one block, as in the built-in card; every other pair gets a divider.
    static func dividesSections(_ previous: MenuCardSectionKind, _ next: MenuCardSectionKind) -> Bool {
        let joined: Set<MenuCardSectionKind> = [.usage, .chart]
        return !(joined.contains(previous) && joined.contains(next))
    }

    /// The model for the usage block alone: no chart and no cost summary, with today's note rules kept.
    static func usageRowsModel(_ model: UsageMenuCardView.Model) -> UsageMenuCardView.Model {
        var rows = model
        rows.cardLayout = .standard
        rows.throughput = nil
        if model.inlineUsageDashboard != nil {
            // With a cost summary the built-in card shows plan notes only, and never the placeholder.
            rows.usageNotes = model.quotaSubscriptionNotes.isEmpty ? model.subscriptionNotes : []
            rows.placeholder = nil
        }
        rows.inlineUsageDashboard = nil
        return rows
    }
}

extension UsageMenuCardView.Model {
    fileprivate var hasCardUsageBlock: Bool {
        !self.metrics.isEmpty ||
            !self.quotaSubscriptionNotes.isEmpty ||
            !self.supplementalUsageNotes.isEmpty ||
            !self.providerDetails.isEmpty ||
            self.limitResetCredits != nil ||
            self.cloudCredits != nil ||
            self.placeholder != nil
    }
}
