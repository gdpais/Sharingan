import SharinganCore

/// Quota warning settings for lanes beyond the session and weekly windows (a provider's third window or a
/// provider-reported extra window). A lane without an override follows the weekly settings, as it always
/// has; an override uses the same `QuotaWarningWindowConfig` shape the windows use.
extension SettingsStore {
    // MARK: - Lane resolution

    /// Thresholds for one quota lane: its own override when the provider config has one, otherwise the
    /// window's thresholds.
    func resolvedQuotaWarningThresholds(
        provider: ProviderInstanceID,
        window: QuotaWarningWindow,
        laneID: String?) -> [Int]
    {
        let fallback = self.resolvedQuotaWarningThresholds(provider: provider, window: window)
        guard let laneID else { return fallback }
        return self.quotaWarningConfig(for: provider).thresholds(forLane: laneID, fallback: fallback)
    }

    func quotaWarningEnabled(provider: UsageProvider, window: QuotaWarningWindow, laneID: String?) -> Bool {
        let fallback = self.quotaWarningEnabled(provider: provider, window: window)
        guard let laneID else { return fallback }
        return self.quotaWarningConfig(for: provider.instanceID).isEnabled(forLane: laneID, fallback: fallback)
    }

    func hasQuotaWarningLaneOverride(provider: UsageProvider, laneID: String) -> Bool {
        self.quotaWarningConfig(for: provider.instanceID).hasLaneOverride(laneID)
    }

    func quotaWarningLaneOverrideIDs(provider: UsageProvider) -> [String] {
        self.quotaWarningConfig(for: provider.instanceID).laneOverrideIDs
    }

    func explicitQuotaWarningLaneThresholds(provider: UsageProvider, laneID: String) -> [Int]? {
        self.quotaWarningConfig(for: provider.instanceID)
            .laneConfig(laneID)?
            .thresholds
            .map(QuotaWarningThresholds.sanitized)
    }

    // MARK: - Lane edits

    /// Replaces a lane's override. Nil thresholds and a nil switch remove it, so the lane follows the
    /// weekly settings again.
    func setQuotaWarningLaneOverride(
        provider: UsageProvider,
        laneID: String,
        thresholds: [Int]?,
        enabled: Bool?)
    {
        let laneConfig = QuotaWarningWindowConfig(thresholds: thresholds, enabled: enabled)
        let desired: QuotaWarningWindowConfig? = laneConfig.hasOverride ? laneConfig : nil
        guard self.quotaWarningConfig(for: provider.instanceID).laneConfig(laneID) != desired else { return }

        self.updateProviderConfig(provider: provider) { entry in
            var config = entry.quotaWarnings ?? QuotaWarningConfig()
            config.setLaneConfig(desired, for: laneID)
            entry.quotaWarnings = config.isEmpty ? nil : config
        }
    }

    /// Stores edited thresholds while the lane is overridden and keeps its switch. Thresholds still
    /// inherited from the weekly window stay inherited until the user changes them.
    func setQuotaWarningLaneThresholdsIfOverridden(provider: UsageProvider, laneID: String, thresholds: [Int]) {
        guard let current = self.quotaWarningConfig(for: provider.instanceID).laneConfig(laneID),
              current.hasOverride
        else { return }

        let sanitized = QuotaWarningThresholds.sanitized(thresholds)
        let currentThresholds = current.thresholds.map(QuotaWarningThresholds.sanitized)
        guard currentThresholds != sanitized else { return }
        let inherited = self.resolvedQuotaWarningThresholds(provider: provider.instanceID, window: .weekly)
        if currentThresholds == nil, sanitized == inherited {
            return
        }

        self.setQuotaWarningLaneOverride(
            provider: provider,
            laneID: laneID,
            thresholds: sanitized,
            enabled: current.enabled)
    }

    // MARK: - Consumers

    /// Usage-bar marker thresholds for every overridden lane: the lane's thresholds while markers show and
    /// the lane warns, empty (no markers) while it is switched off. Lanes left out follow the weekly markers.
    func quotaWarningLaneMarkerThresholds(provider: UsageProvider) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for laneID in self.quotaWarningLaneOverrideIDs(provider: provider) {
            let visible = self.quotaWarningMarkersVisible
                && self.quotaWarningEnabled(provider: provider, window: .weekly, laneID: laneID)
            result[laneID] = visible
                ? self.resolvedQuotaWarningThresholds(provider: provider.instanceID, window: .weekly, laneID: laneID)
                : []
        }
        return result
    }

    /// Severity bands for every lane of a provider, from the same thresholds that drive its warnings.
    func quotaSeverityBandSet(for provider: UsageProvider) -> QuotaSeverityBandSet {
        let instanceID = provider.instanceID
        var lanes: [String: QuotaSeverityBands] = [:]
        for laneID in self.quotaWarningLaneOverrideIDs(provider: provider) {
            lanes[laneID] = QuotaSeverityBands.from(thresholds: self.resolvedQuotaWarningThresholds(
                provider: instanceID,
                window: .weekly,
                laneID: laneID))
        }
        return QuotaSeverityBandSet(
            session: QuotaSeverityBands.from(
                thresholds: self.resolvedQuotaWarningThresholds(provider: instanceID, window: .session)),
            weekly: QuotaSeverityBands.from(
                thresholds: self.resolvedQuotaWarningThresholds(provider: instanceID, window: .weekly)),
            lanes: lanes)
    }
}
