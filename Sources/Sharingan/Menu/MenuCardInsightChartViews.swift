import Charts
import SharinganCore
import SwiftUI

/// Fixed geometry shared by the card's own charts, matching the Live strip: a title line, a 44 pt plot and
/// caption lines below. Heights never depend on the data, so the measured menu height stays valid.
enum MenuCardInsightChartLayout {
    static let plotHeight: CGFloat = 44
    static let spacing: CGFloat = 5
    static let bottomPadding: CGFloat = 10
    static let barSlotRatio = 0.6
    static let currentWindowOpacity = 0.45
}

/// Draws the Burn Down or Plan fit chart chosen for this card, if the layout set one.
struct MenuCardInsightChartSlot: View {
    let model: UsageMenuCardView.Model

    var body: some View {
        if let chart = self.model.cardLayout.insightChart {
            MenuCardInsightChartContent(chart: chart, color: self.model.progressColor)
        }
    }
}

struct MenuCardInsightChartContent: View {
    let chart: MenuCardInsightChart
    let color: Color

    var body: some View {
        switch self.chart {
        case let .burndown(burndown):
            MenuCardBurndownChartContent(chart: burndown, color: self.color)
        case let .planFit(planFit):
            MenuCardPlanFitChartContent(chart: planFit, color: self.color)
        }
    }
}

// MARK: - Burn Down

struct MenuCardBurndownChartContent: View {
    private static let runOutColor = Color(nsColor: .systemRed)

    let chart: MenuCardBurndownChart
    let color: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let model = self.chart.model
        VStack(alignment: .leading, spacing: MenuCardInsightChartLayout.spacing) {
            MenuCardInsightChartTitle(text: self.chart.title)
            Chart {
                ForEach(model.ideal, id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(L("Usage remaining"), point.remainingPercent),
                        series: .value("Series", "Ideal"))
                        .foregroundStyle(ChartReferenceLine.color)
                        .lineStyle(ChartReferenceLine.strokeStyle)
                }
                ForEach(model.projection, id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(L("Usage remaining"), point.remainingPercent),
                        series: .value("Series", "Projection"))
                        .foregroundStyle(model.runOut == nil ? self.lineColor : Self.runOutColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3]))
                }
                ForEach(model.samples, id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(L("Usage remaining"), point.remainingPercent),
                        series: .value("Series", "Observed"))
                        .foregroundStyle(self.lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let runOut = model.runOut {
                    PointMark(
                        x: .value("Time", runOut),
                        y: .value(L("Usage remaining"), 0.0))
                        .foregroundStyle(Self.runOutColor)
                        .symbolSize(20)
                }
            }
            .chartXScale(domain: model.start...model.reset)
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                    .frame(height: 1)
            }
            .frame(height: MenuCardInsightChartLayout.plotHeight)
            .accessibilityLabel(L("Usage remaining"))
            MenuCardInsightChartCaption(text: Self.summary(model: model))
        }
        .padding(.bottom, MenuCardInsightChartLayout.bottomPadding)
    }

    private var lineColor: Color {
        self.isHighlighted ? MenuHighlightStyle.selectionText : self.color
    }

    /// "62% Usage remaining · Runs out in 2d 4h", or "… · Lasts until reset".
    static func summary(model: QuotaBurndownModel) -> String {
        let remaining = model.samples.last?.remainingPercent ?? 0
        let remainingText = "\(remaining.formatted(.number.precision(.fractionLength(0))))% \(L("Usage remaining"))"
        let outlook: String
        if let runOut = model.runOut {
            let duration = UsageFormatter.resetCountdownDuration(from: runOut, now: model.now)
            outlook = duration == "now" ? L("Runs out now") : L("Runs out in %@", duration)
        } else {
            outlook = L("Lasts until reset")
        }
        return "\(remainingText) · \(outlook)"
    }
}

// MARK: - Plan fit

struct MenuCardPlanFitChartContent: View {
    let chart: MenuCardPlanFitChart
    let color: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: MenuCardInsightChartLayout.spacing) {
            MenuCardInsightChartTitle(text: self.chart.title)
            Chart {
                ForEach(self.chart.bars) { bar in
                    RectangleMark(
                        xStart: .value(L("Series"), bar.x - MenuCardInsightChartLayout.barSlotRatio / 2),
                        xEnd: .value(L("Series"), bar.x + MenuCardInsightChartLayout.barSlotRatio / 2),
                        yStart: .value(L("Usage"), 0.0),
                        yEnd: .value(L("Usage"), max(bar.peakPercent, 1)))
                        .foregroundStyle(self.barColor(bar))
                }
                RuleMark(y: .value(L("Limit"), PlanFit.cappedPercent))
                    .foregroundStyle(ChartReferenceLine.color)
                    .lineStyle(ChartReferenceLine.strokeStyle)
                if let median = self.chart.summary.medianPeakPercent {
                    RuleMark(y: .value(L("Median"), median))
                        .foregroundStyle(ChartReferenceLine.color)
                        .lineStyle(ChartReferenceLine.strokeStyle)
                }
            }
            .chartXScale(domain: self.chart.xDomain)
            .chartYScale(domain: 0...PlanFitChartLayout.yDomainTop)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                    .frame(height: 1)
            }
            .frame(height: MenuCardInsightChartLayout.plotHeight)
            .accessibilityLabel(L("Plan utilization chart"))
            // Both caption lines are always reserved, so a verdict change never moves the menu height.
            MenuCardInsightChartCaption(text: PlanFitPresentation.summaryLine(self.chart.summary) ?? " ")
            MenuCardInsightChartCaption(text: PlanFitPresentation.verdictLine(self.chart.summary.verdict))
        }
        .padding(.bottom, MenuCardInsightChartLayout.bottomPadding)
    }

    private func barColor(_ bar: MenuCardPlanFitChart.Bar) -> Color {
        let base: Color = if self.isHighlighted {
            MenuHighlightStyle.selectionText
        } else if bar.isCapped {
            ChartPalette.color(for: self.chart.cappedSlot)
        } else {
            self.color
        }
        return bar.isCurrent ? base.opacity(MenuCardInsightChartLayout.currentWindowOpacity) : base
    }
}

// MARK: - Spend

/// The spend bars on their own, for a card that draws its chart apart from the cost summary. Same strip, title
/// and summary as the Spend side of the Live/Spend switch.
struct MenuCardSpendChartContent: View {
    let dashboard: InlineUsageDashboardModel
    @Environment(\.menuUsageBarSelection) private var injectedSelection
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @State private var selectedPointID: String?

    var body: some View {
        let selection = self.injectedSelection ?? self.$selectedPointID
        VStack(alignment: .leading, spacing: MenuCardInsightChartLayout.spacing) {
            MenuCardInsightChartTitle(text: self.dashboard.chartTitle ?? L(
                "Daily spend · %@",
                L("Last %d days", self.dashboard.points.count)))
            MenuUsageBarStrip(
                points: self.dashboard.points.map(\.menuUsageBarPoint),
                baseColor: self.dashboard.chartColor,
                selection: selection)
                .frame(height: MenuCardInsightChartLayout.plotHeight)
                .accessibilityLabel(self.dashboard.accessibilityLabel)
            MenuCardInsightChartCaption(text: self.dashboard.chartSummary(selectedPointID: selection.wrappedValue))
        }
        .padding(.bottom, MenuCardInsightChartLayout.bottomPadding)
    }
}

// MARK: - Text

private struct MenuCardInsightChartTitle: View {
    let text: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Text(self.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct MenuCardInsightChartCaption: View {
    let text: String
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        Text(self.text)
            .font(.caption)
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}
