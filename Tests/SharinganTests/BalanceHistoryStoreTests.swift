import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

struct BalanceHistoryStoreTests {
    /// Whole seconds: the store encodes ISO 8601 dates without fractional seconds.
    private static let start = Date(timeIntervalSince1970: 1_699_999_200)
    private static let zenmux = UsageProvider.zenmux.instanceID
    private static let openrouter = UsageProvider.openrouter.instanceID

    private static func sample(hours: Double, _ balance: Double) -> BalanceHistorySample {
        BalanceHistorySample(
            capturedAt: self.start.addingTimeInterval(hours * 3600),
            balance: balance,
            currencyCode: "USD")
    }

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BalanceHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("balance-history", isDirectory: true)
    }

    // MARK: - Store

    @Test
    func `store round trips histories through a temporary directory`() {
        let directory = Self.temporaryDirectory()
        let store = BalanceHistoryStore(directoryURL: directory)
        var zenmux = BalanceHistoryBuckets()
        zenmux.setSamples([Self.sample(hours: 0, 10), Self.sample(hours: 1, 9.5)], for: nil)
        zenmux.setSamples([Self.sample(hours: 0, 40)], for: "account-a")
        var openrouter = BalanceHistoryBuckets()
        openrouter.setSamples([Self.sample(hours: 2, 7)], for: "account-b")

        store.save([Self.zenmux: zenmux, Self.openrouter: openrouter])

        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("zenmux.json").path))
        #expect(store.load() == [Self.zenmux: zenmux, Self.openrouter: openrouter])
    }

    @Test
    func `saving empty buckets removes the provider file`() {
        let directory = Self.temporaryDirectory()
        let store = BalanceHistoryStore(directoryURL: directory)
        var buckets = BalanceHistoryBuckets()
        buckets.setSamples([Self.sample(hours: 0, 10)], for: nil)
        store.save([Self.zenmux: buckets])

        store.save([Self.zenmux: BalanceHistoryBuckets()])

        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("zenmux.json").path))
        #expect(store.load().isEmpty)
    }

    @Test
    func `unsupported schema versions are ignored`() throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"version": 999, "unscoped": [], "accounts": {}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("zenmux.json"), options: .atomic)

        #expect(BalanceHistoryStore(directoryURL: directory).load().isEmpty)
    }

    @Test
    func `loading re-applies the retention caps`() throws {
        let directory = Self.temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {
          "version": 1,
          "unscoped": [
            {"capturedAt": "2023-11-14T22:00:00Z", "balance": 9, "currencyCode": "USD"},
            {"capturedAt": "2023-01-01T00:00:00Z", "balance": 50, "currencyCode": "USD"}
          ],
          "accounts": {}
        }
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("zenmux.json"), options: .atomic)

        let loaded = BalanceHistoryStore(directoryURL: directory).load()

        #expect(loaded[Self.zenmux]?.unscoped.map(\.balance) == [9])
    }

    @Test
    func `a store without a directory neither saves nor loads`() {
        let store = BalanceHistoryStore(directoryURL: nil)
        var buckets = BalanceHistoryBuckets()
        buckets.setSamples([Self.sample(hours: 0, 10)], for: nil)

        store.save([Self.zenmux: buckets])

        #expect(store.load().isEmpty)
    }

    // MARK: - Recorder

    @MainActor
    @Test
    func `recorder applies samples recorded before the load finishes`() async {
        let directory = Self.temporaryDirectory()
        let store = BalanceHistoryStore(directoryURL: directory)
        var persisted = BalanceHistoryBuckets()
        persisted.setSamples([Self.sample(hours: 0, 10)], for: nil)
        store.save([Self.zenmux: persisted])
        let recorder = BalanceHistoryRecorder(store: store)

        recorder.record(Self.sample(hours: 2, 9), provider: Self.zenmux, accountKey: nil)
        await recorder._waitForLoadForTesting()

        #expect(recorder.isLoaded)
        #expect(recorder.samples(for: Self.zenmux, accountKey: nil).map(\.balance) == [10, 9])
    }

    @MainActor
    @Test
    func `recorder keeps providers and accounts apart`() async {
        let recorder = BalanceHistoryRecorder(store: BalanceHistoryStore(directoryURL: nil))
        await recorder._waitForLoadForTesting()

        recorder.record(Self.sample(hours: 0, 10), provider: Self.zenmux, accountKey: nil)
        recorder.record(Self.sample(hours: 0, 40), provider: Self.zenmux, accountKey: "account-a")
        recorder.record(Self.sample(hours: 0, 7), provider: Self.openrouter, accountKey: nil)
        recorder.record(Self.sample(hours: 0.5, 7), provider: Self.openrouter, accountKey: nil)

        #expect(recorder.samples(for: Self.zenmux, accountKey: nil).map(\.balance) == [10])
        #expect(recorder.samples(for: Self.zenmux, accountKey: "account-a").map(\.balance) == [40])
        #expect(recorder.samples(for: Self.zenmux, accountKey: "account-b").isEmpty)
        #expect(recorder.samples(for: Self.openrouter, accountKey: nil).map(\.balance) == [7])
    }

    // MARK: - Snapshot reading

    @MainActor
    @Test
    func `usage snapshots are read like the menu card balance`() {
        let balanceOnly = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(used: 12.5, limit: 0, currencyCode: "USD", updatedAt: Self.start),
            updatedAt: Self.start)
        let spendWithBalance = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 3,
                limit: 0,
                currencyCode: "USD",
                balance: 41,
                updatedAt: Self.start),
            updatedAt: Self.start)

        #expect(UsageStore.balanceHistorySample(provider: .zenmux, snapshot: balanceOnly)?.balance == 12.5)
        #expect(UsageStore.balanceHistorySample(provider: .openrouter, snapshot: spendWithBalance)?.balance == 41)
        #expect(UsageStore.balanceHistorySample(
            provider: .zenmux,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: Self.start)) == nil)
    }

    @MainActor
    @Test
    func `snapshots owned by another provider are never recorded`() {
        let foreign = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(used: 12.5, limit: 0, currencyCode: "USD", updatedAt: Self.start),
            updatedAt: Self.start,
            identity: ProviderIdentitySnapshot(
                providerID: Self.openrouter,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil))

        #expect(UsageStore.balanceHistorySample(provider: .zenmux, snapshot: foreign) == nil)
    }

    @MainActor
    @Test
    func `test processes never reach the shared recorder`() {
        #expect(!BalanceHistoryRecorder.isAvailableInProcess)
    }

    @Test
    func `balance history follows the record usage history toggle`() {
        #expect(UsageStore.balanceHistoryIsEnabled(
            historicalTrackingEnabled: true,
            automaticallyStartsBackgroundWork: true,
            isAvailableInProcess: true))
        #expect(!UsageStore.balanceHistoryIsEnabled(
            historicalTrackingEnabled: false,
            automaticallyStartsBackgroundWork: true,
            isAvailableInProcess: true))
        #expect(!UsageStore.balanceHistoryIsEnabled(
            historicalTrackingEnabled: true,
            automaticallyStartsBackgroundWork: false,
            isAvailableInProcess: true))
        #expect(!UsageStore.balanceHistoryIsEnabled(
            historicalTrackingEnabled: true,
            automaticallyStartsBackgroundWork: true))
    }
}
