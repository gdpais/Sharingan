import CodexBarCore
import Foundation

/// The running app's balance history: loaded once from disk, mutated on the main actor, and persisted
/// off it through a coalescing coordinator.
@MainActor
final class BalanceHistoryRecorder {
    /// Shared by the app. Test processes never reach it; see `UsageStore.balanceHistoryRecorder`.
    static let live = BalanceHistoryRecorder(store: .defaultAppSupport())

    /// Checked once: balance history never reads or writes real user files from a test process.
    nonisolated static let isAvailableInProcess = !TestProcessSafety.isRunning

    private static let maximumPendingSamples = 64

    private struct PendingSample {
        let provider: ProviderInstanceID
        let accountKey: String?
        let sample: BalanceHistorySample
    }

    private let store: BalanceHistoryStore
    private let persistence: BalanceHistoryPersistenceCoordinator
    private let retention: BalanceHistoryRetention
    private var histories: [ProviderInstanceID: BalanceHistoryBuckets] = [:]
    private var pendingSamples: [PendingSample] = []
    private var loadTask: Task<Void, Never>?
    private(set) var isLoaded = false

    init(store: BalanceHistoryStore, retention: BalanceHistoryRetention = .standard) {
        self.store = store
        self.persistence = BalanceHistoryPersistenceCoordinator(store: store)
        self.retention = retention
    }

    func startLoadIfNeeded() {
        guard !self.isLoaded, self.loadTask == nil else { return }
        let store = self.store
        self.loadTask = Task { @MainActor [weak self] in
            let loaded = await store.loadAsync()
            self?.finishLoad(loaded)
        }
    }

    func record(_ sample: BalanceHistorySample, provider: ProviderInstanceID, accountKey: String?) {
        guard self.isLoaded else {
            // Applying samples before the first decode would overwrite disk history with a near-empty
            // snapshot, so they wait for the load instead.
            if self.pendingSamples.count < Self.maximumPendingSamples {
                self.pendingSamples.append(PendingSample(provider: provider, accountKey: accountKey, sample: sample))
            }
            self.startLoadIfNeeded()
            return
        }
        if self.apply(sample, provider: provider, accountKey: accountKey) {
            self.enqueuePersistence()
        }
    }

    func samples(for provider: ProviderInstanceID, accountKey: String?) -> [BalanceHistorySample] {
        self.startLoadIfNeeded()
        return self.histories[provider]?.samples(for: accountKey) ?? []
    }

    private func finishLoad(_ loaded: [ProviderInstanceID: BalanceHistoryBuckets]) {
        guard !self.isLoaded else { return }
        self.histories = loaded
        self.isLoaded = true
        let pending = self.pendingSamples
        self.pendingSamples.removeAll()
        var changed = false
        for entry in pending {
            let applied = self.apply(entry.sample, provider: entry.provider, accountKey: entry.accountKey)
            changed = changed || applied
        }
        if changed {
            self.enqueuePersistence()
        }
    }

    private func apply(_ sample: BalanceHistorySample, provider: ProviderInstanceID, accountKey: String?) -> Bool {
        var buckets = self.histories[provider] ?? BalanceHistoryBuckets()
        guard let updated = BalanceHistory.appending(
            sample,
            to: buckets.samples(for: accountKey),
            retention: self.retention)
        else { return false }
        buckets.setSamples(updated, for: accountKey)
        self.histories[provider] = buckets
        return true
    }

    private func enqueuePersistence() {
        let snapshot = self.histories
        let persistence = self.persistence
        Task {
            await persistence.enqueue(snapshot)
        }
    }

    #if DEBUG
    func _waitForLoadForTesting() async {
        self.startLoadIfNeeded()
        await self.loadTask?.value
    }
    #endif
}

extension UsageStore {
    /// The app's recorder, or nil where balance history must not touch the user's files (tests, previews).
    var balanceHistoryRecorder: BalanceHistoryRecorder? {
        guard self.startupBehavior.automaticallyStartsBackgroundWork,
              BalanceHistoryRecorder.isAvailableInProcess
        else { return nil }
        return BalanceHistoryRecorder.live
    }

    /// Records the prepaid balance of a freshly published snapshot.
    ///
    /// Called from `emitUsageUpdatedHook`, which every successful refresh publication passes through
    /// (provider refreshes, Codex accounts, selected token accounts) once the generation is current.
    func recordBalanceHistorySample(provider instanceID: ProviderInstanceID, snapshot: UsageSnapshot) {
        guard let provider = instanceID.firstPartyProvider,
              let recorder = self.balanceHistoryRecorder,
              let sample = Self.balanceHistorySample(provider: provider, snapshot: snapshot)
        else { return }
        recorder.record(
            sample,
            provider: instanceID,
            accountKey: self.balanceHistoryAccountKey(provider: provider, snapshot: snapshot))
    }

    /// The balance sample a snapshot carries, read the same way the menu card reads its balance.
    static func balanceHistorySample(provider: UsageProvider, snapshot: UsageSnapshot) -> BalanceHistorySample? {
        // Never attribute another provider's identity or balance to this provider's history.
        if let ownerID = snapshot.identity?.providerID, ownerID != provider.instanceID {
            return nil
        }
        guard let cost = snapshot.providerCost else { return nil }
        let style = ProviderDescriptorRegistry.descriptor(for: provider).presentation
            .cost(snapshot: snapshot)
            .menuCardStyle
        return BalanceHistory.sample(cost: cost, style: style)
    }

    /// Token-account scope first, then the snapshot's own account identity, else the provider's unscoped
    /// history. Reuses the plan-history keys, which are hashed, so no identity is written to disk.
    func balanceHistoryAccountKey(provider: UsageProvider, snapshot: UsageSnapshot?) -> String? {
        if let tokenAccountKey = Self.planUtilizationAccountKey(
            provider: provider,
            account: self.settings.effectiveSelectedTokenAccount(for: provider))
        {
            return tokenAccountKey
        }
        return snapshot.flatMap { Self.planUtilizationIdentityAccountKey(provider: provider, snapshot: $0) }
    }

    /// Runway chart for the provider's current account, or nil when there is no balance on the card or
    /// not enough declining history for an estimate.
    func balanceRunwayChartModel(for provider: UsageProvider, now: Date = Date()) -> BalanceRunwayChartModel? {
        guard let recorder = self.balanceHistoryRecorder,
              let snapshot = self.snapshot(for: provider.instanceID),
              Self.balanceHistorySample(provider: provider, snapshot: snapshot) != nil
        else { return nil }
        let presentation = ProviderDescriptorRegistry.descriptor(for: provider).presentation
        guard presentation.menuCard.showsProviderCost(context: ProviderCostVisibilityContext(
            snapshot: snapshot,
            showOptionalUsage: self.settings.showOptionalCreditsAndExtraUsage))
        else { return nil }

        let samples = recorder.samples(
            for: provider.instanceID,
            accountKey: self.balanceHistoryAccountKey(provider: provider, snapshot: snapshot))
        guard let estimate = BalanceRunwayModel.estimate(samples: samples),
              estimate.depletionDate > now
        else { return nil }
        return BalanceRunwayChartModel(samples: samples, estimate: estimate)
    }
}
