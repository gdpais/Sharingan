import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension HistoricalUsagePaceTests {
    @MainActor
    @Test
    func `typical week inputs follow the learned pace account and provider`() throws {
        let store = try Self.makeUsageStoreForHistoricalTests(
            suite: "HistoricalUsagePaceTests-typical-week-inputs",
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: Self.makeTempURL()))
        store.settings._test_liveSystemCodexAccount = Self.liveAccount(email: "person@example.com")
        defer { store.settings._test_liveSystemCodexAccount = nil }
        let resetsAt = Date(timeIntervalSince1970: 1_770_000_000)
        store.codexHistoricalDataset = CodexHistoricalDataset(weeks: [
            HistoricalWeekProfile(resetsAt: resetsAt, windowMinutes: 10080, curve: [0, 40, 80]),
        ])
        let accountKey = store.codexOwnershipContext().canonicalKey
        store.codexHistoricalDatasetAccountKey = accountKey

        #expect(store.typicalWeekInputs(for: .codex) == [
            TypicalWeekCurve.Week(resetsAt: resetsAt, windowMinutes: 10080, usedPercent: [0, 40, 80]),
        ])
        #expect(store.typicalWeekInputs(for: .claude).isEmpty)

        // Weeks learned for another account never describe this one.
        store.codexHistoricalDatasetAccountKey = "fixture-other-account"
        #expect(store.typicalWeekInputs(for: .codex).isEmpty)

        store.codexHistoricalDatasetAccountKey = accountKey
        store.settings.historicalTrackingEnabled = false
        #expect(store.typicalWeekInputs(for: .codex).isEmpty)
    }
}
