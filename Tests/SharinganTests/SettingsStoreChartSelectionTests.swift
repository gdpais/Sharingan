import Foundation
import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct SettingsStoreChartSelectionTests {
    @Test
    func `cost history metric persists independently per provider`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let originalConfig = try encoder.encode(settings.config)

        #expect(settings.costHistoryChartMetric(for: .codex) == nil)
        settings.setCostHistoryChartMetric(.cost, for: .codex)
        settings.setCostHistoryChartMetric(.tokens, for: .claude)
        #expect(settings.costHistoryChartMetric(for: .codex) == .cost)
        #expect(settings.costHistoryChartMetric(for: .claude) == .tokens)

        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.costHistoryChartMetric(for: .codex) == .cost)
        #expect(reloaded.costHistoryChartMetric(for: .claude) == .tokens)
        #expect(try encoder.encode(settings.config) == originalConfig)

        defaults.set([UsageProvider.codex.rawValue: "unknown"], forKey: "costHistoryChartMetrics")
        #expect(settings.costHistoryChartMetric(for: .codex) == nil)
    }

    @Test
    func `plan utilization series selection persists independently per provider`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)

        #expect(settings.planUtilizationSeriesID(for: .codex) == nil)
        settings.setPlanUtilizationSeriesID("weekly:10080", for: .codex)
        settings.setPlanUtilizationSeriesID("session:300", for: .claude)

        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.planUtilizationSeriesID(for: .codex) == "weekly:10080")
        #expect(reloaded.planUtilizationSeriesID(for: .claude) == "session:300")
        #expect(reloaded.planUtilizationSeriesID(for: .kiro) == nil)
    }

    @Test
    func `remembered cost metric applies only while the data can chart it`() {
        let both = [
            CostUsageDailyReport.Entry(
                date: "2026-06-01",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: 1000,
                costUSD: 2,
                modelsUsed: nil,
                modelBreakdowns: nil),
        ]
        let costOnly = [
            CostUsageDailyReport.Entry(
                date: "2026-06-01",
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                costUSD: 2,
                modelsUsed: nil,
                modelBreakdowns: nil),
        ]
        #expect(CostHistoryChartMenuView._defaultMetricForTesting(provider: .codex, daily: both) == .tokens)
        #expect(CostHistoryChartMenuView._initialMetricForTesting(
            preferred: .cost, provider: .codex, daily: both) == .cost)
        #expect(CostHistoryChartMenuView._initialMetricForTesting(
            preferred: .tokens, provider: .codex, daily: costOnly) == .cost)
        #expect(CostHistoryChartMenuView._initialMetricForTesting(
            preferred: nil, provider: .codex, daily: both) == .tokens)
    }
}
