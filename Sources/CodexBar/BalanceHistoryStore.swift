import CodexBarCore
import Foundation

/// Balance samples for one provider, split by account so accounts never share a runway.
struct BalanceHistoryBuckets: Equatable, Sendable {
    var unscoped: [BalanceHistorySample] = []
    var accounts: [String: [BalanceHistorySample]] = [:]

    func samples(for accountKey: String?) -> [BalanceHistorySample] {
        guard let accountKey, !accountKey.isEmpty else { return self.unscoped }
        return self.accounts[accountKey] ?? []
    }

    mutating func setSamples(_ samples: [BalanceHistorySample], for accountKey: String?) {
        guard let accountKey, !accountKey.isEmpty else {
            self.unscoped = samples
            return
        }
        if samples.isEmpty {
            self.accounts.removeValue(forKey: accountKey)
        } else {
            self.accounts[accountKey] = samples
        }
    }

    var isEmpty: Bool {
        self.unscoped.isEmpty && self.accounts.values.allSatisfy(\.isEmpty)
    }
}

private struct BalanceHistoryDocument: Codable, Sendable {
    let version: Int
    let unscoped: [BalanceHistorySample]
    let accounts: [String: [BalanceHistorySample]]
}

/// File-backed balance history, one JSON document per provider instance.
///
/// Mirrors `PlanUtilizationHistoryStore`: Application Support, atomic writes that skip unchanged
/// payloads, a nil directory for tests and non-persisting stores, and best-effort error handling.
struct BalanceHistoryStore: Sendable {
    fileprivate static let schemaVersion = 1

    let directoryURL: URL?

    init(directoryURL: URL? = Self.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    static func defaultAppSupport() -> Self {
        Self()
    }

    /// Loads persisted histories off the main thread.
    func loadAsync() async -> [ProviderInstanceID: BalanceHistoryBuckets] {
        await Task.detached(priority: .utility) { self.load() }.value
    }

    /// Writes each given provider's document; providers with no samples have their file removed.
    func save(_ providers: [ProviderInstanceID: BalanceHistoryBuckets]) {
        guard let directoryURL = self.directoryURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]

            for instanceID in providers.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                let fileURL = self.providerFileURL(for: instanceID)
                let buckets = Self.sanitized(providers[instanceID] ?? BalanceHistoryBuckets())
                guard !buckets.isEmpty else {
                    try? FileManager.default.removeItem(at: fileURL)
                    continue
                }

                let payload = BalanceHistoryDocument(
                    version: Self.schemaVersion,
                    unscoped: buckets.unscoped,
                    accounts: buckets.accounts)
                let data = try encoder.encode(payload)
                if let existingData = try? Data(contentsOf: fileURL),
                   existingData == data
                {
                    continue
                }
                try data.write(to: fileURL, options: Data.WritingOptions.atomic)
            }
        } catch {
            // Best-effort persistence only.
        }
    }

    func load() -> [ProviderInstanceID: BalanceHistoryBuckets] {
        guard let directoryURL = self.directoryURL,
              let fileURLs = try? FileManager.default.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: nil)
        else { return [:] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var output: [ProviderInstanceID: BalanceHistoryBuckets] = [:]
        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            guard let instanceID = ProviderInstanceID(rawValue: fileURL.deletingPathExtension().lastPathComponent),
                  let data = try? Data(contentsOf: fileURL),
                  let decoded = try? decoder.decode(BalanceHistoryDocument.self, from: data)
            else { continue }

            let buckets = Self.sanitized(BalanceHistoryBuckets(
                unscoped: decoded.unscoped,
                accounts: decoded.accounts))
            if !buckets.isEmpty {
                output[instanceID] = buckets
            }
        }
        return output
    }

    /// Re-applies ordering and the retention caps, so hand-edited or older files stay bounded.
    private static func sanitized(_ buckets: BalanceHistoryBuckets) -> BalanceHistoryBuckets {
        var accounts: [String: [BalanceHistorySample]] = [:]
        for (accountKey, samples) in buckets.accounts where !accountKey.isEmpty {
            let pruned = BalanceHistory.pruned(samples.filter(\.balance.isFinite))
            if !pruned.isEmpty {
                accounts[accountKey] = pruned
            }
        }
        return BalanceHistoryBuckets(
            unscoped: BalanceHistory.pruned(buckets.unscoped.filter(\.balance.isFinite)),
            accounts: accounts)
    }

    private static func defaultDirectoryURL() -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = root.appendingPathComponent(AppIdentity.reverseDNS, isDirectory: true)
        return dir.appendingPathComponent("balance-history", isDirectory: true)
    }

    private func providerFileURL(for instanceID: ProviderInstanceID) -> URL {
        let directoryURL = self.directoryURL ?? URL(fileURLWithPath: "/dev/null", isDirectory: true)
        return directoryURL.appendingPathComponent("\(instanceID.rawValue).json", isDirectory: false)
    }
}

extension BalanceHistoryDocument {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == BalanceHistoryStore.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported balance history schema version \(version)")
        }
        self.version = version
        self.unscoped = try container.decodeIfPresent([BalanceHistorySample].self, forKey: .unscoped) ?? []
        self.accounts = try container.decodeIfPresent(
            [String: [BalanceHistorySample]].self,
            forKey: .accounts) ?? [:]
    }
}

/// Coalesces saves so only the newest histories are written, off the main actor.
actor BalanceHistoryPersistenceCoordinator {
    private let store: BalanceHistoryStore
    private var pendingSnapshot: [ProviderInstanceID: BalanceHistoryBuckets]?
    private var isPersisting: Bool = false

    init(store: BalanceHistoryStore) {
        self.store = store
    }

    func enqueue(_ snapshot: [ProviderInstanceID: BalanceHistoryBuckets]) {
        self.pendingSnapshot = snapshot
        guard !self.isPersisting else { return }
        self.isPersisting = true

        Task(priority: .utility) {
            await self.persistLoop()
        }
    }

    private func persistLoop() async {
        while let nextSnapshot = self.pendingSnapshot {
            self.pendingSnapshot = nil
            await self.saveAsync(nextSnapshot)
        }

        self.isPersisting = false
    }

    private func saveAsync(_ snapshot: [ProviderInstanceID: BalanceHistoryBuckets]) async {
        let store = self.store
        await Task.detached(priority: .utility) {
            store.save(snapshot)
        }.value
    }
}
