import Foundation
import SharinganCore

// MARK: - Codex quota history backfill from rollout logs

/// Backfills Codex session/weekly plan-utilization history from the `rate_limits` snapshots Codex writes into its
/// local rollout logs, so a fresh install shows history immediately instead of waiting for new samples.
///
/// Account scoping: a rollout only names the ChatGPT account that created it (`session_meta.creator_account_id`,
/// absent in older logs), never the configured Codex account. The backfill therefore runs only while exactly one
/// Codex account is configured (no token accounts, no adjacent multi-account evidence) and merges into the account key
/// the live sample just resolved. Rollouts created by a different ChatGPT account than the configured workspace are
/// skipped; once logs name any foreign account, rollouts without a creator are skipped too. Without a known workspace
/// ID, a named creator cannot be matched to the configured account, so logs are attributed only while no rollout names
/// a creator. Creator IDs are remembered (hashed) so a later incremental pass keeps that veto.
extension UsageStore {
    struct CodexLogQuotaBackfillState: Codable, Equatable, Sendable {
        /// Start of the last complete pass; rollouts modified before it were already read.
        var scannedThrough: Date?
        /// Hashed `creator_account_id` values the rollouts have named so far.
        var creatorAccountIDHashes: [String]
    }

    struct CodexLogQuotaBackfillAttribution: Equatable, Sendable {
        let samples: [CodexRateLimitLogSample]
        let creatorAccountIDHashes: Set<String>
    }

    nonisolated static let codexLogQuotaBackfillStatesDefaultsKey = "codexLogQuotaBackfillStatesV1"
    /// The two years `planUtilizationMaxSamples` hourly entries can hold.
    nonisolated static let codexLogQuotaBackfillLookback: TimeInterval = 730 * 24 * 60 * 60
    /// Re-read rollouts touched shortly before the last pass; merging is idempotent, so overlap is harmless.
    private nonisolated static let codexLogQuotaBackfillWatermarkSlack: TimeInterval = 60 * 60

    @MainActor
    private static var codexLogQuotaBackfillAttemptedAccountKeys: Set<String> = []

    /// Starts at most one backfill pass per history account per launch, after a live Codex sample resolved its owner.
    func startCodexLogQuotaBackfillIfNeeded(provider: UsageProvider, accountKey: String?) {
        guard provider == .codex,
              self.startupBehavior.automaticallyStartsBackgroundWork,
              let accountKey,
              !accountKey.isEmpty,
              !Self.codexLogQuotaBackfillAttemptedAccountKeys.contains(accountKey),
              // Tests must never read the real ~/.codex, even from a store started with `.full` behavior.
              !TestProcessSafety.isRunning
        else { return }
        // One decision per account and launch; an account change mid-launch is picked up on the next launch.
        Self.codexLogQuotaBackfillAttemptedAccountKeys.insert(accountKey)
        guard self.codexLogQuotaBackfillAccountsAreUnambiguous() else { return }

        let previous = self.codexLogQuotaBackfillStates()[accountKey]
        let modifiedSince = previous?.scannedThrough?.addingTimeInterval(-Self.codexLogQuotaBackfillWatermarkSlack)
        let codexHomePath = self.tokenCostScope(for: .codex).codexHomePath
        let startedAt = Date()
        let horizon = startedAt.addingTimeInterval(-Self.codexLogQuotaBackfillLookback)
        Task { @MainActor [weak self] in
            let scan = await Task.detached(priority: .utility) {
                CodexRateLimitLogScanner.scan(
                    codexHomePath: codexHomePath,
                    modifiedSince: modifiedSince,
                    horizon: horizon,
                    now: startedAt)
            }.value
            self?.applyCodexLogQuotaBackfill(
                scan,
                accountKey: accountKey,
                previous: previous,
                startedAt: startedAt,
                horizon: horizon)
        }
    }

    private func applyCodexLogQuotaBackfill(
        _ scan: CodexRateLimitLogScan,
        accountKey: String,
        previous: CodexLogQuotaBackfillState?,
        startedAt: Date,
        horizon: Date)
    {
        // The account set or the live history owner can change while the logs are read.
        guard self.planUtilizationHistoryLoaded, self.codexLogQuotaBackfillAccountsAreUnambiguous() else { return }
        var providerBuckets = self.planUtilizationHistory[.codex] ?? PlanUtilizationHistoryBuckets()
        guard providerBuckets.preferredAccountKey == accountKey else { return }

        let attribution = Self.codexLogQuotaBackfillAttribution(
            scan.samples,
            accountWorkspaceID: self.settings.codexVisibleAccounts.first?.workspaceAccountID,
            knownCreatorAccountIDHashes: Set(previous?.creatorAccountIDHashes ?? []))
        var states = self.codexLogQuotaBackfillStates()
        states[accountKey] = CodexLogQuotaBackfillState(
            scannedThrough: scan.isComplete ? startedAt : previous?.scannedThrough,
            creatorAccountIDHashes: attribution.creatorAccountIDHashes.sorted())
        self.persistPlanUtilizationStates(
            states,
            defaultsKey: Self.codexLogQuotaBackfillStatesDefaultsKey,
            logName: "Codex log quota backfill")

        guard let updatedHistories = PlanUtilizationHistoryStore.codexHistoriesBackfillingLogSamples(
            attribution.samples,
            into: providerBuckets.histories(for: accountKey),
            notBefore: horizon)
        else { return }
        providerBuckets.setHistories(updatedHistories, for: accountKey)
        self.planUtilizationHistory[.codex] = providerBuckets
        self.planUtilizationHistoryRevision &+= 1
        self.sessionEquivalentBurnCache.removeValue(forKey: .codex)
        let snapshotToPersist = self.planUtilizationHistory
        Task {
            await self.planUtilizationPersistenceCoordinator.enqueue(snapshotToPersist)
        }
    }

    private func codexLogQuotaBackfillAccountsAreUnambiguous() -> Bool {
        Self.codexLogQuotaBackfillAllowsAccounts(
            visibleAccountCount: self.settings.codexVisibleAccounts.count,
            tokenAccountCount: self.settings.tokenAccounts(for: .codex).count,
            hasAdjacentMultiAccountVeto: self.codexHasAdjacentMultiAccountVeto())
    }

    private func codexLogQuotaBackfillStates() -> [String: CodexLogQuotaBackfillState] {
        Self.loadPlanUtilizationStates(
            from: self.settings.userDefaults,
            defaultsKey: Self.codexLogQuotaBackfillStatesDefaultsKey,
            logName: "Codex log quota backfill")
    }

    /// Rollout logs cannot name the configured Codex account, so only a single-account setup can own them.
    nonisolated static func codexLogQuotaBackfillAllowsAccounts(
        visibleAccountCount: Int,
        tokenAccountCount: Int,
        hasAdjacentMultiAccountVeto: Bool) -> Bool
    {
        visibleAccountCount == 1 && tokenAccountCount == 0 && !hasAdjacentMultiAccountVeto
    }

    /// Keeps the samples that can belong to the single configured account (see the type comment for the rules).
    nonisolated static func codexLogQuotaBackfillAttribution(
        _ samples: [CodexRateLimitLogSample],
        accountWorkspaceID: String?,
        knownCreatorAccountIDHashes: Set<String>) -> CodexLogQuotaBackfillAttribution
    {
        var hashesByCreator: [String: String] = [:]
        for creator in Set(samples.compactMap(\.creatorAccountID)) {
            hashesByCreator[creator] = Self.codexLogQuotaBackfillAccountIDHash(creator)
        }
        let creatorHashes = knownCreatorAccountIDHashes.union(hashesByCreator.values)
        let accountHash = CodexOpenAIWorkspaceResolver.normalizeWorkspaceAccountID(accountWorkspaceID)
            .map { Self.codexLogQuotaBackfillAccountIDHash($0) }

        let attributable: [CodexRateLimitLogSample]
        if let accountHash {
            let hasForeignCreator = creatorHashes.contains { $0 != accountHash }
            attributable = samples.filter { sample in
                guard let creator = sample.creatorAccountID else { return !hasForeignCreator }
                return hashesByCreator[creator] == accountHash
            }
        } else {
            // Even a single named creator may be an account the user signed out of before configuring this one.
            attributable = creatorHashes.isEmpty ? samples : []
        }
        return CodexLogQuotaBackfillAttribution(samples: attributable, creatorAccountIDHashes: creatorHashes)
    }

    /// Expects an already-normalized (trimmed, lowercased) ChatGPT account ID.
    nonisolated static func codexLogQuotaBackfillAccountIDHash(_ normalizedAccountID: String) -> String {
        self.sha256Hex("codex:log-quota-backfill-account:\(normalizedAccountID)")
    }
}
