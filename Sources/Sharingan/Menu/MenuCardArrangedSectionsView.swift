import SharinganCore
import SwiftUI

/// Draws a card's sections one after another in the order its card layout sets.
///
/// The built-in arrangement interleaves some sections (the cost summary sits under the chart), so the card uses
/// it whenever the layout keeps the default order. Once sections move, each one is drawn as a single block
/// with the same subviews, and a divider between blocks except between usage rows and the chart.
struct MenuCardArrangedSectionsView: View {
    let model: UsageMenuCardView.Model
    let layoutModel: UsageMenuCardView.Model
    let order: [MenuCardSectionKind]
    /// False for a split menu's usage row, whose credits, extra usage and cost are separate menu rows.
    var includesStandaloneSections = true
    var showBottomDivider = false

    var body: some View {
        let blocks = MenuCardArrangement.blocks(
            for: self.model,
            order: self.order,
            includesStandaloneSections: self.includesStandaloneSections)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.element) { index, kind in
                if index > 0, MenuCardArrangement.dividesSections(blocks[index - 1], kind) {
                    Divider()
                }
                self.block(kind)
            }
            if self.showBottomDivider {
                Divider()
            }
        }
    }

    @ViewBuilder
    private func block(_ kind: MenuCardSectionKind) -> some View {
        switch kind {
        case .usage:
            UsageMenuCardUsageContentView(
                model: MenuCardArrangement.usageRowsModel(self.model),
                layoutModel: self.layoutModel,
                showBottomDivider: false)
        case .pace:
            EmptyView()
        case .chart:
            MenuCardChartSlotContent(model: self.model)
        case .credits:
            if let credits = self.model.creditsText {
                CreditsBarContent(
                    creditsText: credits,
                    showsProgress: self.model.creditsShowProgress,
                    progressPercent: self.model.creditsProgressPercent,
                    scaleText: self.model.creditsScaleText,
                    hintText: self.model.creditsHintText,
                    hintCopyText: self.model.creditsHintCopyText,
                    progressColor: self.model.progressColor)
            }
        case .extraUsage:
            if let providerCost = self.model.providerCost {
                ProviderCostContent(section: providerCost, progressColor: self.model.progressColor)
            }
        case .cost:
            MenuCardCostSectionContent(
                model: self.model,
                includesTokenUsage: self.includesStandaloneSections)
        }
    }
}

/// The card's chart slot: the provider's Live/Spend switch or Live strip, the chosen Burn Down or Plan fit
/// chart, or the spend bars alone.
struct MenuCardChartSlotContent: View {
    let model: UsageMenuCardView.Model

    var body: some View {
        if self.model.showsChartSwitch, let throughput = self.model.throughput,
           let dashboard = self.model.inlineUsageDashboard
        {
            ProviderMenuChartContent(
                provider: self.model.provider.instanceID,
                throughput: throughput,
                dashboard: dashboard,
                color: self.model.progressColor)
                .id(self.model.provider.instanceID)
        } else if let throughput = self.model.throughput {
            ProviderThroughputContent(section: throughput, color: self.model.progressColor)
        } else if let chart = self.model.cardLayout.insightChart {
            MenuCardInsightChartContent(chart: chart, color: self.model.progressColor)
        } else if let dashboard = self.model.inlineUsageDashboard, !dashboard.points.isEmpty {
            MenuCardSpendChartContent(dashboard: dashboard)
        }
    }
}

/// The cost section: the inline cost summary without its bars, then the token cost lines.
struct MenuCardCostSectionContent: View {
    let model: UsageMenuCardView.Model
    let includesTokenUsage: Bool

    var body: some View {
        let dashboard = self.model.inlineUsageDashboard.flatMap { $0.hasNonChartContent ? $0 : nil }
        VStack(alignment: .leading, spacing: 12) {
            if let dashboard {
                InlineUsageDashboardContent(model: dashboard, showsChart: false)
            }
            if self.includesTokenUsage, let tokenUsage = self.model.tokenUsage {
                if dashboard != nil {
                    Divider()
                }
                TokenUsageSectionContent(
                    provider: self.model.provider,
                    tokenUsage: tokenUsage,
                    showsCodexHint: self.model.inlineUsageDashboard == nil,
                    lineFont: .footnote)
            }
        }
    }
}
