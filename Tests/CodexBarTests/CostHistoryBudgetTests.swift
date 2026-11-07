import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CostHistoryBudgetTests {
    @Test
    func `budget line values convert into the chart's display currency`() throws {
        // A EUR budget on a USD snapshot shown in GBP: 1 USD = 0.9 EUR = 0.8 GBP.
        let status = Self.status(budget: 50, cost: 18, isComplete: true)
        let budget = try #require(CostHistoryBudget(
            status: status,
            sourceToBudget: 0.9,
            displayCurrencyCode: "GBP",
            sourceToDisplay: 0.8))
        #expect(budget.currencyCode == "GBP")
        #expect(abs(budget.chartDailyShare - 50.0 / 30.0 / 0.9) < 1e-9)
        #expect(abs(budget.monthlyBudget - 50 * 0.8 / 0.9) < 1e-9)
        #expect(abs(budget.monthToDateCost - 18 * 0.8 / 0.9) < 1e-9)
        #expect(abs(budget.dailyShare - budget.chartDailyShare * 0.8) < 1e-9)
        #expect(CostHistoryBudget(
            status: status,
            sourceToBudget: 0,
            displayCurrencyCode: "USD",
            sourceToDisplay: 1) == nil)
    }

    @Test
    func `the month to date line says when history covers only part of the month`() throws {
        let complete = try #require(CostHistoryBudget(
            status: Self.status(budget: 50, cost: 12.4, isComplete: true),
            sourceToBudget: 1,
            displayCurrencyCode: "USD",
            sourceToDisplay: 1))
        let partial = try #require(CostHistoryBudget(
            status: Self.status(budget: 50, cost: 12.4, isComplete: false),
            sourceToBudget: 1,
            displayCurrencyCode: "USD",
            sourceToDisplay: 1))
        let texts = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            (complete.monthToDateText, partial.monthToDateText, complete.dailyShareText)
        }
        #expect(texts.0 == "Month to date $12.40 of $50.00 budget")
        #expect(texts.1 == "Month to date at least $12.40 of $50.00 budget")
        #expect(texts.2 == "budget $1.67/day")
    }

    @Test
    func `the y axis reaches the daily budget on the cost metric only`() throws {
        let budget = try #require(CostHistoryBudget(
            status: Self.status(budget: 150, cost: 0, isComplete: true),
            sourceToBudget: 1,
            displayCurrencyCode: "USD",
            sourceToDisplay: 1))
        #expect(CostHistoryChartMenuView.budgetScaleMaximum(1, budget: budget, metric: .cost) == 5)
        #expect(CostHistoryChartMenuView.budgetScaleMaximum(10, budget: budget, metric: .cost) == 10)
        #expect(CostHistoryChartMenuView.budgetScaleMaximum(1, budget: budget, metric: .tokens) == 1)
        #expect(CostHistoryChartMenuView.budgetScaleMaximum(1, budget: nil, metric: .cost) == 1)
    }

    @Test
    func `the render fingerprint changes with the budget`() {
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: 3,
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2026-11-17",
                    inputTokens: 1000,
                    outputTokens: 0,
                    totalTokens: 1000,
                    costUSD: 3,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_795_000_000))
        let plain = CostHistoryChartMenuView.renderFingerprint(from: snapshot, provider: .claude)
        #expect(plain.budget == nil)
        var budgeted = plain
        budgeted.budget = CostHistoryBudget(
            status: Self.status(budget: 50, cost: 3, isComplete: true),
            sourceToBudget: 1,
            displayCurrencyCode: "USD",
            sourceToDisplay: 1)
        #expect(budgeted != plain)
    }

    @Test
    func `budget notifications say which threshold and how much was spent`() {
        let status = Self.status(budget: 50, cost: 41, isComplete: true)
        let copies = CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            (
                SpendBudgetNotificationLogic.notificationCopy(
                    providerName: "Claude",
                    status: status,
                    percent: 80,
                    currencyCode: "USD"),
                SpendBudgetNotificationLogic.notificationCopy(
                    providerName: "Claude",
                    status: status,
                    percent: 100,
                    currencyCode: "USD"))
        }
        #expect(copies.0.title == "Claude budget at 80%")
        #expect(copies.0.body == "Estimated spend this month: $41.00 of your $50.00 budget.")
        #expect(copies.1.title == "Claude budget reached")
        #expect(SpendBudgetNotificationLogic.notificationIDPrefix(provider: .claude, status: status, percent: 80)
            == "spend-budget-claude-2026-11-80")
    }

    private static func status(budget: Double, cost: Double, isComplete: Bool) -> SpendBudgetStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-11-18 12:00:00 UTC: a 30-day month.
        let month = SpendBudgetMonth.containing(Date(timeIntervalSince1970: 1_795_003_200), calendar: calendar)!
        return SpendBudgetStatus(month: month, budget: budget, monthToDateCost: cost, isComplete: isComplete)
    }
}
