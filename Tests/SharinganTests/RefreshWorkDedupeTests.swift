import Foundation
import SharinganCore
import Testing
@testable import Sharingan

struct RefreshWorkDedupeTests {
    private static func tokenSnapshot(cost: Double, updatedAt: TimeInterval) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: cost,
            last30DaysTokens: 100,
            last30DaysCostUSD: cost,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: updatedAt))
    }

    private static func publication(_ snapshot: CostUsageTokenSnapshot?) -> CurrentProviderConfigTokenPublication {
        CurrentProviderConfigTokenPublication(snapshot: snapshot, publicationRevision: 1, accounting: nil)
    }

    @Test
    func `token content changes on first publication and on new usage only`() {
        let first = Self.tokenSnapshot(cost: 2, updatedAt: 1_800_000_000)
        let rescanned = Self.tokenSnapshot(cost: 2, updatedAt: 1_800_000_900)
        let changed = Self.tokenSnapshot(cost: 3, updatedAt: 1_800_000_900)

        #expect(UsageStore.tokenSnapshotContentChanged(from: nil, to: first))
        #expect(UsageStore.tokenSnapshotContentChanged(from: nil, to: nil))
        #expect(!UsageStore.tokenSnapshotContentChanged(from: Self.publication(first), to: rescanned))
        #expect(UsageStore.tokenSnapshotContentChanged(from: Self.publication(first), to: changed))
        #expect(UsageStore.tokenSnapshotContentChanged(from: Self.publication(first), to: nil))
        #expect(UsageStore.tokenSnapshotContentChanged(from: Self.publication(nil), to: first))
        #expect(!UsageStore.tokenSnapshotContentChanged(from: Self.publication(nil), to: nil))
    }

    @Test
    func `widget snapshot saves when new or changed and skips when unchanged`() {
        let saved = Data("saved".utf8)
        #expect(UsageStore.shouldSaveWidgetSnapshot(fingerprint: saved, lastSavedFingerprint: nil))
        #expect(UsageStore.shouldSaveWidgetSnapshot(fingerprint: nil, lastSavedFingerprint: saved))
        #expect(UsageStore.shouldSaveWidgetSnapshot(fingerprint: Data("new".utf8), lastSavedFingerprint: saved))
        #expect(!UsageStore.shouldSaveWidgetSnapshot(fingerprint: saved, lastSavedFingerprint: saved))
    }

    @Test
    func `plan history persistence rewrites only providers whose buckets changed`() {
        var codex = PlanUtilizationHistoryBuckets()
        codex.preferredAccountKey = "a"
        var claude = PlanUtilizationHistoryBuckets()
        claude.preferredAccountKey = "b"
        let previous: [ProviderInstanceID: PlanUtilizationHistoryBuckets] = [.codex: codex, .claude: claude]

        typealias Coordinator = PlanUtilizationHistoryPersistenceCoordinator
        #expect(Coordinator.changedInstanceIDs(from: previous, to: previous).isEmpty)

        var updatedClaude = claude
        updatedClaude.preferredAccountKey = "c"
        #expect(Coordinator.changedInstanceIDs(
            from: previous,
            to: [.codex: codex, .claude: updatedClaude]) == [.claude])
        // A provider dropped from the snapshot must still have its file reconciled.
        #expect(Coordinator.changedInstanceIDs(from: previous, to: [.codex: codex]) == [.claude])
        #expect(Coordinator.changedInstanceIDs(from: [:], to: previous) == [.codex, .claude])
    }

    @Test
    func `restricted plan history save leaves other provider files untouched`() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshWorkDedupeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlanUtilizationHistoryStore(directoryURL: directory)
        var codex = PlanUtilizationHistoryBuckets()
        codex.sessionEquivalentWindowPairIdentities = ["pair": "one"]
        var claude = PlanUtilizationHistoryBuckets()
        claude.sessionEquivalentWindowPairIdentities = ["pair": "one"]
        #expect(store.save([.codex: codex, .claude: claude]))
        #expect(store.load() == [.codex: codex, .claude: claude])

        // Only Claude is named as changed, so Codex keeps its file even though the snapshot differs.
        var updatedCodex = codex
        updatedCodex.sessionEquivalentWindowPairIdentities = ["pair": "ignored"]
        var updatedClaude = claude
        updatedClaude.sessionEquivalentWindowPairIdentities = ["pair": "two"]
        #expect(store.save([.codex: updatedCodex, .claude: updatedClaude], changedInstanceIDs: [.claude]))
        #expect(store.load() == [.codex: codex, .claude: updatedClaude])

        // An emptied provider named as changed has its file removed.
        #expect(store.save([.codex: codex], changedInstanceIDs: [.claude]))
        #expect(store.load() == [.codex: codex])
    }
}
