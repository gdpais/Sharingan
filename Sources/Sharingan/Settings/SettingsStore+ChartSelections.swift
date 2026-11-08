import Foundation
import SharinganCore

/// Local, per-provider chart choices remembered across menu openings. Stored like `providerMenuChartModes`:
/// a `[String: String]` defaults dictionary keyed by the provider's raw value, outside the synced config.
extension SettingsStore {
    private static let costHistoryChartMetricsKey = "costHistoryChartMetrics"
    private static let planUtilizationSeriesSelectionsKey = "planUtilizationSeriesSelections"

    func costHistoryChartMetric(for provider: UsageProvider) -> CostHistoryChartMenuView.ChartMetric? {
        self.chartSelection(forKey: Self.costHistoryChartMetricsKey, provider: provider)
            .flatMap(CostHistoryChartMenuView.ChartMetric.init(rawValue:))
    }

    func setCostHistoryChartMetric(_ metric: CostHistoryChartMenuView.ChartMetric, for provider: UsageProvider) {
        self.setChartSelection(metric.rawValue, forKey: Self.costHistoryChartMetricsKey, provider: provider)
    }

    /// The `PlanUtilizationHistoryChartMenuView.SeriesSelection.id` last picked for this provider.
    func planUtilizationSeriesID(for provider: UsageProvider) -> String? {
        self.chartSelection(forKey: Self.planUtilizationSeriesSelectionsKey, provider: provider)
    }

    func setPlanUtilizationSeriesID(_ seriesID: String, for provider: UsageProvider) {
        self.setChartSelection(seriesID, forKey: Self.planUtilizationSeriesSelectionsKey, provider: provider)
    }

    private func chartSelection(forKey key: String, provider: UsageProvider) -> String? {
        let selections = self.userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return selections[provider.rawValue]
    }

    private func setChartSelection(_ value: String, forKey key: String, provider: UsageProvider) {
        var selections = self.userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
        guard selections[provider.rawValue] != value else { return }
        selections[provider.rawValue] = value
        self.userDefaults.set(selections, forKey: key)
    }
}
