import Foundation
import SharinganCore

/// The newest status request a provider has published, and when. Older overlapping requests may not replace it.
struct ProviderStatusPublication {
    var generation: UInt64
    var publishedAt: Date
}

extension UsageStore {
    func refreshProviderStatus(_ provider: UsageProvider) async {
        guard self.settings.statusChecksEnabled else { return }
        guard let meta = self.providerMetadata[provider] else { return }
        let publicationRevision = self.providerPublicationRevision(for: provider)
        self.providerStatusRequestGeneration &+= 1
        let requestGeneration = self.providerStatusRequestGeneration

        do {
            let status: ProviderStatus
            var components: [ProviderStatusComponent]?
            if let override = self._test_providerStatusFetchOverride {
                status = try await override(provider)
            } else if let urlString = meta.statusPageURL, let baseURL = URL(string: urlString) {
                let summary = try await ProviderStatusFetcher.fetchStatusSummary(from: baseURL)
                status = summary.status
                components = summary.components
            } else if let productID = meta.statusWorkspaceProductID {
                status = try await ProviderStatusFetcher.fetchWorkspaceStatus(productID: productID)
            } else {
                return
            }
            guard self.statusRefreshPublicationIsCurrent(
                publicationRevision, requestGeneration: requestGeneration, for: provider) else { return }
            // A failed newer request provides no status evidence, so only a successful
            // publication retires earlier requests for this provider.
            self.providerStatusPublications[provider.instanceID] = ProviderStatusPublication(
                generation: requestGeneration,
                publishedAt: Date())
            self.statuses[provider.instanceID] = status
            // A component endpoint is best-effort. Preserve the last good list when the
            // overall status succeeds but the component request or decoding fails.
            if let components {
                self.statusComponents[provider.instanceID] = components
            }
            self.emitProviderStatusHooks(provider: provider, indicator: status.indicator)
        } catch {
            guard self.statusRefreshPublicationIsCurrent(
                publicationRevision, requestGeneration: requestGeneration, for: provider) else { return }
            self.recordStartupConnectivityRetryableFailure(error)
            // A failed fetch provides no new status information. Preserve a last good status
            // to avoid flapping, or leave it unset until the first successful fetch.
        }
    }

    /// Whether a refresh pass should poll this provider's status page. A manual refresh and a startup
    /// connectivity pass (the launch refresh or its retry) always do; otherwise the status is reused until
    /// `ProviderStatusRefreshPolicy` says it is due. Failed fetches publish nothing, so they retry on the next
    /// refresh, and a cleared status is always due.
    func statusRefreshIsDue(
        _ provider: UsageProvider,
        among availableProviders: Set<ProviderInstanceID>,
        mode: RefreshEnrichmentMode,
        now: Date = Date()) -> Bool
    {
        let id = provider.instanceID
        guard availableProviders.contains(id) else { return false }
        guard mode != .forcedForeground, !self.startupConnectivityRetryRefreshActive else { return true }
        return ProviderStatusRefreshPolicy.isDue(
            lastSuccessAt: self.providerStatusPublications[id]?.publishedAt,
            indicator: self.statuses[id]?.indicator,
            now: now)
    }

    private func statusRefreshPublicationIsCurrent(
        _ publicationRevision: ProviderPublicationRevision,
        requestGeneration: UInt64,
        for provider: UsageProvider) -> Bool
    {
        self.providerPublicationRevisionIsCurrent(publicationRevision, for: provider) &&
            requestGeneration >= (self.providerStatusPublications[provider.instanceID]?.generation ?? 0) &&
            self.settings.statusChecksEnabled &&
            self.settings.isProviderEnabledCached(
                provider: provider,
                metadataByProvider: self.providerMetadata)
    }
}
