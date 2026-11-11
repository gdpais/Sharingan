import Foundation
import Testing
@testable import SharinganCore

struct RefreshWorkDedupeTests {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_800_000_000)

        var now: Date {
            self.lock.withLock { self.value }
        }

        func advance(by interval: TimeInterval) {
            self.lock.withLock { self.value = self.value.addingTimeInterval(interval) }
        }
    }

    private static func tokenSnapshot(cost: Double, updatedAt: Date) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 10,
            sessionCostUSD: cost,
            last30DaysTokens: 100,
            last30DaysCostUSD: cost,
            daily: [],
            updatedAt: updatedAt)
    }

    @Test
    func `token snapshots that differ only in timestamp report the same content`() {
        let first = Self.tokenSnapshot(cost: 2, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let rescanned = Self.tokenSnapshot(cost: 2, updatedAt: Date(timeIntervalSince1970: 1_800_000_900))
        let changed = Self.tokenSnapshot(cost: 3, updatedAt: Date(timeIntervalSince1970: 1_800_000_900))

        #expect(first != rescanned)
        #expect(first.hasSameContent(as: rescanned))
        #expect(rescanned.hasSameContent(as: first))
        #expect(!first.hasSameContent(as: changed))
    }

    @Test
    func `widget fingerprint ignores generation time and tracks content`() throws {
        let first = WidgetSnapshot(
            entries: [],
            enabledProviders: [.codex],
            usageBarsShowUsed: true,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let republished = WidgetSnapshot(
            entries: [],
            enabledProviders: [.codex],
            usageBarsShowUsed: true,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_300))
        let changed = WidgetSnapshot(
            entries: [],
            enabledProviders: [.codex],
            usageBarsShowUsed: false,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_300))

        let fingerprint = try #require(first.contentFingerprint())
        #expect(fingerprint == republished.contentFingerprint())
        #expect(fingerprint != changed.contentFingerprint())
    }

    @Test
    func `decoded ledgers idle past the limit are dropped on the next ledger access`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshWorkDedupeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock()
        let store = CostUsageClaudeFragments(idleLimit: 60, now: { clock.now })
        let window = directory.appendingPathComponent("window.json")
        let history = directory.appendingPathComponent("history.json")

        _ = try store.save(header: "window", values: ["/a/one": 1], at: window)
        _ = try store.save(header: "history", values: ["/a/one": 1, "/b/two": 2], at: history)
        #expect(store.retainedSnapshotCount == 2)

        // The window ledger keeps being read; the history ledger is not.
        clock.advance(by: 45)
        _ = try store.load(at: window, legacy: Self.rejectLegacy) as (String, [String: Int])
        #expect(store.retainedSnapshotCount == 2)
        clock.advance(by: 45)
        _ = try store.load(at: window, legacy: Self.rejectLegacy) as (String, [String: Int])
        #expect(store.retainedSnapshotCount == 1)

        // An evicted ledger reloads from disk with its content intact.
        let reloaded: (String, [String: Int]) = try store.load(at: history, legacy: Self.rejectLegacy)
        #expect(reloaded.0 == "history")
        #expect(reloaded.1 == ["/a/one": 1, "/b/two": 2])
        #expect(store.retainedSnapshotCount == 2)
    }

    @Test
    func `releasing ledgers drops every snapshot and keeps them loadable`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshWorkDedupeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CostUsageClaudeFragments()
        let url = directory.appendingPathComponent("window.json")
        _ = try store.save(header: "window", values: ["/a/one": 1], at: url)

        #expect(store.removeAll() == 1)
        #expect(store.retainedSnapshotCount == 0)
        let reloaded: (String, [String: Int]) = try store.load(at: url, legacy: Self.rejectLegacy)
        #expect(reloaded.1 == ["/a/one": 1])
        #expect(store.retainedSnapshotCount == 1)
    }

    private static func rejectLegacy(_: Data) throws -> (String, [String: Int]) {
        throw CocoaError(.fileReadCorruptFile)
    }
}
