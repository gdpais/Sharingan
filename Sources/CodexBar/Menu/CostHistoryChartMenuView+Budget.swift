import Charts
import CodexBarCore
import SwiftUI

/// A provider's monthly budget as the cost history chart shows it: a dashed reference at the budget's
/// daily share and a month-to-date line under the total.
///
/// Label amounts are in the chart's display currency. `chartDailyShare` is in the chart's own units,
/// the snapshot's cost currency before the display multiplier, so the reference sits on the bars' scale.
struct CostHistoryBudget: Equatable, Sendable {
    let currencyCode: String
    let monthlyBudget: Double
    let monthToDateCost: Double
    let dailyShare: Double
    let chartDailyShare: Double
    let isComplete: Bool

    /// - Parameters:
    ///   - sourceToBudget: Converts the snapshot's cost currency into the budget's currency.
    ///   - sourceToDisplay: Converts the snapshot's cost currency into the chart's display currency.
    init?(
        status: SpendBudgetStatus,
        sourceToBudget: Double,
        displayCurrencyCode: String,
        sourceToDisplay: Double)
    {
        guard sourceToBudget.isFinite, sourceToBudget > 0, sourceToDisplay.isFinite, sourceToDisplay > 0 else {
            return nil
        }
        let budgetToDisplay = sourceToDisplay / sourceToBudget
        self.currencyCode = displayCurrencyCode
        self.monthlyBudget = status.budget * budgetToDisplay
        self.monthToDateCost = status.monthToDateCost * budgetToDisplay
        self.dailyShare = status.dailyShare * budgetToDisplay
        self.chartDailyShare = status.dailyShare / sourceToBudget
        self.isComplete = status.isComplete
    }

    /// "Month to date $12.40 of $50.00 budget"; "at least" when history does not cover the whole month.
    var monthToDateText: String {
        let spent = UsageFormatter.currencyString(self.monthToDateCost, currencyCode: self.currencyCode)
        let budget = UsageFormatter.currencyString(self.monthlyBudget, currencyCode: self.currencyCode)
        return self.isComplete
            ? L("Month to date %@ of %@ budget", spent, budget)
            : L("Month to date at least %@ of %@ budget", spent, budget)
    }

    var dailyShareText: String {
        L("budget %@/day", UsageFormatter.currencyString(self.dailyShare, currencyCode: self.currencyCode))
    }

    var drawsReference: Bool {
        self.chartDailyShare.isFinite && self.chartDailyShare > 0
    }
}

extension CostHistoryChartMenuView {
    static let budgetLineHeight: CGFloat = 16

    /// The y-axis reaches the budget reference, so the dashed line always sits inside the plot.
    static func budgetScaleMaximum(_ maxValue: Double, budget: CostHistoryBudget?, metric: ChartMetric) -> Double {
        guard metric == .cost, let budget, budget.drawsReference else { return maxValue }
        return max(maxValue, budget.chartDailyShare)
    }

    /// The budget's daily share as a dashed reference, on the cost metric only.
    @ChartContentBuilder
    static func budgetReference(_ budget: CostHistoryBudget?, metric: ChartMetric) -> some ChartContent {
        if metric == .cost, let budget, budget.drawsReference {
            RuleMark(y: .value(L("Budget"), budget.chartDailyShare))
                .foregroundStyle(ChartReferenceLine.color)
                .lineStyle(ChartReferenceLine.strokeStyle)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text(budget.dailyShareText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(budget.dailyShareText)
        }
    }
}

/// The month-to-date line under the cost total. A single fixed-height row, present only with a budget,
/// and shown for both metrics so switching metrics never changes the menu's measured height.
struct CostHistoryBudgetLine: View {
    let budget: CostHistoryBudget

    var body: some View {
        Text(self.budget.monthToDateText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: CostHistoryChartMenuView.budgetLineHeight, alignment: .leading)
            .accessibilityIdentifier("cost-history-budget-line")
    }
}
