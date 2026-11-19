import Foundation
import SharinganCore

struct SpendSourcePublication: Sendable, Equatable {
    enum Role: Sendable, Equatable {
        case subscription
        case enrichment
        case localHistory
    }

    enum State: Sendable, Equatable {
        case loading
        case available
        case confirmedEmpty
        case unavailable
        case staleLastKnown
    }

    let id: String
    let provider: UsageProvider?
    let displayName: String
    let role: Role
    let state: State
}

struct SpendDashboardPublication: Sendable {
    let revision: UInt64
    let generation: UInt64
    let configuration: SpendDashboardConfiguration?
    let loadedAt: Date
    let isRefreshing: Bool
    let inputs: [SpendDashboardModel.ProviderInput]
    let sources: [SpendSourcePublication]

    static let empty = SpendDashboardPublication(
        revision: 0,
        generation: 0,
        configuration: nil,
        loadedAt: .distantPast,
        isRefreshing: false,
        inputs: [],
        sources: [])

    func model(
        requestedDays: Int,
        reportingPeriod: CostReportingPeriod? = nil,
        now: Date,
        calendar: Calendar,
        preferredCurrencyCode: String,
        hiddenSourceIDs: Set<String> = [],
        hideNativeCodexWhenOpenCodexPresent: Bool = false,
        selectedDay: Date? = nil,
        providerScope: Set<UsageProvider>? = nil,
        fallbackInputs: [SpendDashboardModel.ProviderInput] = []) -> SpendDashboardModel
    {
        let staleSourceIDs = self.staleSourceIDs
        let inputs = self.inputs.filter { input in
            (providerScope?.contains(input.provider) ?? true) && !staleSourceIDs.contains(input.id)
        } + fallbackInputs.filter { fallback in
            (providerScope?.contains(fallback.provider) ?? true) &&
                !self.inputs.contains { $0.provider == fallback.provider && !staleSourceIDs.contains($0.id) }
        }
        return SpendDashboardModel.build(
            inputs: inputs,
            requestedDays: requestedDays,
            reportingPeriod: reportingPeriod,
            now: now,
            calendar: calendar,
            preferredCurrencyCode: preferredCurrencyCode,
            hiddenSourceIDs: hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: hideNativeCodexWhenOpenCodexPresent,
            selectedDay: selectedDay)
    }

    private var staleSourceIDs: Set<String> {
        Set(self.sources.compactMap { source in
            source.state == .staleLastKnown ? source.id : nil
        })
    }

    /// Subscription providers in scope that this publication cannot price right now: every source is
    /// still loading, unavailable, or only retained as stale last-known data. Leaving them out of a
    /// total that sits beside their own provider cards would understate spend (a provider card shows
    /// its 30-day cost while the overview total silently omits it), so callers substitute a fallback.
    func providersMissingFreshSubscriptionInput(
        providerScope: Set<UsageProvider>,
        hiddenSourceIDs: Set<String> = []) -> Set<UsageProvider>
    {
        let staleSourceIDs = self.staleSourceIDs
        return providerScope.filter { provider in
            let sources = self.sources.filter { $0.provider == provider }
            guard sources.contains(where: { $0.role == .subscription }),
                  !hiddenSourceIDs.contains(provider.rawValue),
                  !sources.contains(where: { hiddenSourceIDs.contains($0.id) || $0.state == .confirmedEmpty })
            else { return false }
            return !self.inputs.contains { $0.provider == provider && !staleSourceIDs.contains($0.id) }
        }
    }

    /// The retained last-known input for a provider whose latest dashboard refresh failed.
    func staleLastKnownInput(for provider: UsageProvider) -> SpendDashboardModel.ProviderInput? {
        let staleSourceIDs = self.staleSourceIDs
        return self.inputs.first { $0.provider == provider && staleSourceIDs.contains($0.id) }
    }

    func subscriptionCount(
        providerScope: Set<UsageProvider>,
        hiddenSourceIDs: Set<String> = [],
        hideNativeCodexWhenOpenCodexPresent: Bool = false) -> Int
    {
        providerScope.reduce(into: 0) { count, provider in
            let rosterSources = self.subscriptionRosterSources(for: provider)
            let coverageSources = self.coverageSources(
                for: provider,
                hiddenSourceIDs: hiddenSourceIDs,
                hideNativeCodexWhenOpenCodexPresent: hideNativeCodexWhenOpenCodexPresent)
            if rosterSources.isEmpty, coverageSources.isEmpty {
                let hasVisibleLocalHistory = self.sources.contains {
                    $0.provider == provider &&
                        $0.role == .localHistory &&
                        !hiddenSourceIDs.contains($0.id)
                }
                if !hasVisibleLocalHistory {
                    count += hiddenSourceIDs.contains(provider.rawValue) ? 0 : 1
                }
            } else {
                count += coverageSources.count
            }
        }
    }

    func knownCostSubscriptionCount(
        model: SpendDashboardModel,
        providerScope: Set<UsageProvider>,
        hiddenSourceIDs: Set<String> = [],
        hideNativeCodexWhenOpenCodexPresent: Bool = false) -> Int
    {
        let knownInputIDs = Set(model.groups.flatMap(\.providers).compactMap { row in
            row.totalCost == nil ? nil : row.id
        })
        return self.knownSubscriptionCount(
            knownInputIDs: knownInputIDs,
            providerScope: providerScope,
            hiddenSourceIDs: hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: hideNativeCodexWhenOpenCodexPresent)
    }

    func knownTokenSubscriptionCount(
        model: SpendDashboardModel,
        providerScope: Set<UsageProvider>,
        hiddenSourceIDs: Set<String> = [],
        hideNativeCodexWhenOpenCodexPresent: Bool = false) -> Int
    {
        let knownInputIDs = Set(model.groups.flatMap(\.providers).compactMap { row in
            row.totalTokens == nil ? nil : row.id
        })
        return self.knownSubscriptionCount(
            knownInputIDs: knownInputIDs,
            providerScope: providerScope,
            hiddenSourceIDs: hiddenSourceIDs,
            hideNativeCodexWhenOpenCodexPresent: hideNativeCodexWhenOpenCodexPresent)
    }

    private func knownSubscriptionCount(
        knownInputIDs: Set<String>,
        providerScope: Set<UsageProvider>,
        hiddenSourceIDs: Set<String>,
        hideNativeCodexWhenOpenCodexPresent: Bool) -> Int
    {
        providerScope.reduce(into: 0) { count, provider in
            count += self.coverageSources(
                for: provider,
                hiddenSourceIDs: hiddenSourceIDs,
                hideNativeCodexWhenOpenCodexPresent: hideNativeCodexWhenOpenCodexPresent)
                .count { source in
                    source.state == .confirmedEmpty ||
                        (source.state == .available && knownInputIDs.contains(source.id))
                }
        }
    }

    private func subscriptionRosterSources(for provider: UsageProvider) -> [SpendSourcePublication] {
        self.sources.filter { $0.provider == provider && $0.role == .subscription }
    }

    private func coverageSources(
        for provider: UsageProvider,
        hiddenSourceIDs: Set<String>,
        hideNativeCodexWhenOpenCodexPresent: Bool) -> [SpendSourcePublication]
    {
        let rosterSources = self.subscriptionRosterSources(for: provider)
            .filter { !hiddenSourceIDs.contains($0.id) }
        // Provider-specific by design: OpenCodex replaces Codex coverage only with a canonical Codex payload.
        guard provider == .codex else { return rosterSources }
        let visibleOpenCodexInputIDs: Set<String> = Set(self.inputs.compactMap { input -> String? in
            guard input.provider == .codex,
                  input.sourceKind == .openCodex,
                  !hiddenSourceIDs.contains(input.id)
            else { return nil }
            return input.id
        })
        let inputBackedEnrichmentSources = self.sources.filter {
            $0.provider == .codex &&
                $0.role == .enrichment &&
                visibleOpenCodexInputIDs.contains($0.id)
        }
        let canonicalReplacement = inputBackedEnrichmentSources.first {
            $0.id == SpendDashboardModel.openCodexSourceID
        }
        if hideNativeCodexWhenOpenCodexPresent,
           let canonicalReplacement,
           canonicalReplacement.state == SpendSourcePublication.State.available
        {
            return [canonicalReplacement]
        }
        if rosterSources.isEmpty, !inputBackedEnrichmentSources.isEmpty {
            return inputBackedEnrichmentSources
        }
        // Provider-specific by design: only canonical Codex enrichment can replace Codex subscription coverage.
        guard self.subscriptionRosterSources(for: provider).isEmpty,
              !hiddenSourceIDs.contains(SpendDashboardModel.openCodexSourceID),
              let openCodexObservation = self.sources.first(where: {
                  $0.id == SpendDashboardModel.openCodexSourceID &&
                      $0.provider == .codex &&
                      $0.role == .enrichment
              })
        else { return rosterSources }
        let hasCodexReplacementInput = self.inputs.contains {
            $0.id == SpendDashboardModel.openCodexSourceID &&
                $0.provider == .codex &&
                $0.sourceKind == .openCodex
        }
        return hasCodexReplacementInput || openCodexObservation.state == .confirmedEmpty
            ? [openCodexObservation]
            : rosterSources
    }
}
