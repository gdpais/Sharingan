import AppKit
import SharinganCore
import SwiftUI
import Testing
@testable import Sharingan

@MainActor
struct CostHistoryChartStackingTests {
    private typealias Model = CostUsageDailyReport.ModelBreakdown

    // MARK: - Stacking

    @Test
    func `stacked chart legends the top two models and folds the rest into other`() throws {
        let stack = try #require(CostHistoryChartMenuView._stackForTesting(
            provider: .claude,
            daily: Self.threeModelDays,
            metric: .cost))
        #expect(stack.models == ["fixture-alpha", "fixture-beta"])
        #expect(stack.legendItems.map(\.title) == ["fixture-alpha", "fixture-beta", L("Other")])
        #expect(stack.legendItems.map(\.isOther) == [false, false, true])
        #expect(stack.stackedDayKeys.sorted() == ["2026-06-05", "2026-06-06"])
    }

    @Test
    func `stacked segments keep every bar at its plotted total`() throws {
        let stack = try #require(CostHistoryChartMenuView._stackForTesting(
            provider: .claude,
            daily: Self.threeModelDays,
            metric: .cost))
        var topByDate: [Date: Double] = [:]
        for segment in stack.segments {
            #expect(segment.start < segment.end)
            topByDate[segment.date] = max(topByDate[segment.date] ?? 0, segment.end)
        }
        let plotted = CostHistoryChartMenuView._chartValuesForTesting(
            provider: .claude,
            daily: Self.threeModelDays,
            metric: .cost)
        // The breakdown-free day keeps its single bar, so only the stacked days are compared.
        #expect(topByDate.values.sorted() == plotted.filter { $0 != 3 }.sorted())
        #expect(stack.stackedDates.count == 2)
    }

    @Test
    func `token metric stacks by tokens`() throws {
        let stack = try #require(CostHistoryChartMenuView._stackForTesting(
            provider: .claude,
            daily: Self.threeModelDays,
            metric: .tokens))
        // Gamma is the cheapest model but the chattiest one.
        #expect(stack.models == ["fixture-gamma", "fixture-alpha"])
    }

    @Test
    func `charts without model breakdowns are not stacked and reserve no legend`() {
        let daily = [
            Self.entry("2026-06-05", cost: 2, tokens: 200, models: nil),
            Self.entry("2026-06-06", cost: 3, tokens: 300, models: []),
        ]
        for metric in [CostHistoryChartMenuView.ChartMetric.cost, .tokens] {
            let stack = CostHistoryChartMenuView._stackForTesting(provider: .claude, daily: daily, metric: metric)
            #expect(stack?.models == nil)
            #expect(!CostHistoryChartMenuView._reservesStackLegendRowForTesting(
                provider: .claude,
                daily: daily,
                metric: metric))
        }
    }

    @Test
    func `legend row stays reserved when only the other metric stacks`() {
        let tokensOnly = [
            Self.entry("2026-06-05", cost: 2, tokens: 200, models: [
                Model(modelName: "fixture-alpha", costUSD: nil, totalTokens: 150),
                Model(modelName: "fixture-beta", costUSD: nil, totalTokens: 50),
            ]),
        ]
        let costStack = CostHistoryChartMenuView._stackForTesting(provider: .claude, daily: tokensOnly, metric: .cost)
        let tokenStack = CostHistoryChartMenuView._stackForTesting(
            provider: .claude,
            daily: tokensOnly,
            metric: .tokens)
        #expect(costStack?.models == nil)
        #expect(tokenStack?.models == ["fixture-alpha", "fixture-beta"])
        #expect(CostHistoryChartMenuView._reservesStackLegendRowForTesting(
            provider: .claude,
            daily: tokensOnly,
            metric: .cost))
    }

    @Test
    func `fitting height does not change when the metric switches`() {
        let tokensOnly = [
            Self.entry("2026-06-05", cost: 2, tokens: 200, models: [
                Model(modelName: "fixture-alpha", costUSD: nil, totalTokens: 150),
                Model(modelName: "fixture-beta", costUSD: nil, totalTokens: 50),
            ]),
            Self.entry("2026-06-06", cost: 1, tokens: 100, models: [
                Model(modelName: "fixture-alpha", costUSD: nil, totalTokens: 100),
            ]),
        ]
        #expect(Self.renderedHeight(daily: tokensOnly, initialMetric: .cost)
            == Self.renderedHeight(daily: tokensOnly, initialMetric: .tokens))
    }

    @Test
    func `turning stacking off drops the legend row`() {
        let stacked = Self.renderedHeight(daily: Self.threeModelDays, initialMetric: .cost)
        let flat = Self.renderedHeight(daily: Self.threeModelDays, initialMetric: .cost, stackByModel: false)
        #expect(flat < stacked)
    }

    @Test
    func `stacked day rows take their legend colors`() throws {
        let daily = Self.threeModelDays
        let stack = try #require(CostHistoryChartMenuView._stackForTesting(
            provider: .claude,
            daily: daily,
            metric: .cost))
        let view = CostHistoryChartMenuView(
            provider: .claude,
            daily: daily,
            totalCostUSD: 15,
            hidePersonalInfo: false,
            width: 320)
        let entry = daily.first { $0.date == "2026-06-05" }
        let rows = view.breakdownRows(entry: entry, barColor: .blue, stack: stack)
        #expect(rows.map(\.title) == ["fixture-alpha", "fixture-beta", "fixture-gamma"])
        #expect(rows.map(\.accentColor) == [
            ChartPalette.color(for: .index(0)),
            ChartPalette.color(for: .index(1)),
            ChartPalette.otherColor,
        ])
        // Without a stack the rows keep their provider-accent ramp.
        let unstacked = view.breakdownRows(entry: entry, barColor: .blue)
        #expect(unstacked.map(\.title) == rows.map(\.title))
        #expect(unstacked.first?.accentColor != ChartPalette.color(for: .index(0)))
    }

    // MARK: - Previous period

    @Test
    func `previous period delta reads as a signed percentage of the window`() throws {
        try SharinganLocalizationOverride.$appLanguage.withValue("en") {
            let up = try #require(CostHistoryChartMenuView.previousPeriodDeltaText(
                currentCostUSD: 112,
                previousPeriodCostUSD: 100,
                historyDays: 30,
                incompleteCount: 0))
            #expect(up.contains("+"))
            #expect(up.contains("12"))
            #expect(up.hasSuffix("vs previous 30 days"))

            let down = try #require(CostHistoryChartMenuView.previousPeriodDeltaText(
                currentCostUSD: 50,
                previousPeriodCostUSD: 100,
                historyDays: 7,
                incompleteCount: 0))
            #expect(!down.contains("+"))
            #expect(down.contains("50"))
            #expect(down.hasSuffix("vs previous 7 days"))
        }
    }

    @Test
    func `previous period delta is hidden without an honest comparison`() {
        let hidden: [(Double?, Double?, Int, Int)] = [
            (112, nil, 30, 0),
            (112, 0, 30, 0),
            (nil, 100, 30, 0),
            (112, 100, 1, 0),
            (112, 100, 30, 2),
        ]
        for (current, previous, days, incomplete) in hidden {
            #expect(CostHistoryChartMenuView.previousPeriodDeltaText(
                currentCostUSD: current,
                previousPeriodCostUSD: previous,
                historyDays: days,
                incompleteCount: incomplete) == nil)
        }
    }

    // MARK: - Fixtures

    /// Alpha leads on cost, beta follows, gamma has the most tokens; the third day has no breakdown.
    private static var threeModelDays: [CostUsageDailyReport.Entry] {
        [
            self.entry("2026-06-05", cost: 10, tokens: 1000, models: [
                Model(modelName: "fixture-alpha", costUSD: 6, totalTokens: 200),
                Model(modelName: "fixture-beta", costUSD: 3, totalTokens: 100),
                Model(modelName: "fixture-gamma", costUSD: 1, totalTokens: 700),
            ]),
            self.entry("2026-06-06", cost: 5, tokens: 500, models: [
                Model(modelName: "fixture-alpha", costUSD: 4, totalTokens: 100),
                Model(modelName: "fixture-gamma", costUSD: 1, totalTokens: 400),
            ]),
            self.entry("2026-06-07", cost: 3, tokens: 300, models: nil),
        ]
    }

    private static func entry(
        _ date: String,
        cost: Double?,
        tokens: Int?,
        models: [CostUsageDailyReport.ModelBreakdown]?) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: models?.map(\.modelName),
            modelBreakdowns: models)
    }

    private static func renderedHeight(
        daily: [CostUsageDailyReport.Entry],
        initialMetric: CostHistoryChartMenuView.ChartMetric,
        stackByModel: Bool = true) -> CGFloat
    {
        let hosting = MenuHostingView(rootView: CostHistoryChartMenuView(
            provider: .claude,
            daily: daily,
            totalCostUSD: nil,
            stackByModel: stackByModel,
            hidePersonalInfo: false,
            width: 320,
            initialMetric: initialMetric))
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 1)
        hosting.layoutSubtreeIfNeeded()
        return ceil(hosting.fittingSize.height)
    }
}
