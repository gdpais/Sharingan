import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

@MainActor
struct ProviderStatusRefreshPublicationTests {
    @Test
    func `late scoped status cannot replace a newer background status`() async {
        let store = Self.makeStore()
        let gate = StatusPublicationGate()
        var requests = 0
        store._test_providerStatusFetchOverride = { _ in
            requests += 1
            if requests == 1 {
                await gate.suspend()
                return Self.status(.none, description: "Older operational status")
            }
            return Self.status(.major, description: "Current incident")
        }

        let scopedRefresh = Task {
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await store.refreshProvider(.codex)
                await store.refreshProviderStatus(.codex)
            }
        }
        await gate.waitUntilStarted()
        #expect(!store.isRefreshing)
        let completed = await store.runRefresh(startupConnectivityRetryAttempt: nil)
        #expect(completed)
        #expect(requests == 2)
        #expect(store.statuses[.codex]?.description == "Current incident")
        #expect(store.providerStatusHadIssue[.codex] == true)

        await gate.resume()
        await scopedRefresh.value

        #expect(store.statuses[.codex]?.description == "Current incident")
        #expect(store.providerStatusHadIssue[.codex] == true)
        await store.creditsRefreshTask?.value
        await store.tokenRefreshSequenceTask?.value
        store.memoryPressureReliefTask?.cancel()
        await store.memoryPressureReliefTask?.value
    }

    @Test
    func `a newer request can publish after an overlapping older success`() async {
        let store = Self.makeStore()
        let olderGate = StatusPublicationGate()
        let newerGate = StatusPublicationGate()
        var requests = 0
        store._test_providerStatusFetchOverride = { _ in
            requests += 1
            if requests == 1 {
                await olderGate.suspend()
                return Self.status(.none, description: "Older operational status")
            }
            await newerGate.suspend()
            return Self.status(.major, description: "Current incident")
        }

        let older = Task { await store.refreshProviderStatus(.codex) }
        await olderGate.waitUntilStarted()
        let newer = Task { await store.refreshProviderStatus(.codex) }
        await newerGate.waitUntilStarted()
        await olderGate.resume()
        await older.value
        #expect(store.statuses[.codex]?.description == "Older operational status")
        await newerGate.resume()
        await newer.value

        #expect(store.statuses[.codex]?.description == "Current incident")
        #expect(store.providerStatusHadIssue[.codex] == true)
    }

    @Test
    func `an older success remains useful when a newer request fails`() async {
        let store = Self.makeStore()
        let gate = StatusPublicationGate()
        var requests = 0
        store._test_providerStatusFetchOverride = { _ in
            requests += 1
            if requests == 1 {
                await gate.suspend()
                return Self.status(.major, description: "Available incident")
            }
            throw URLError(.timedOut)
        }

        let older = Task { await store.refreshProviderStatus(.codex) }
        await gate.waitUntilStarted()
        await store.refreshProviderStatus(.codex)
        #expect(store.statuses[.codex] == nil)
        await gate.resume()
        await older.value

        #expect(store.statuses[.codex]?.description == "Available incident")
        #expect(store.providerStatusHadIssue[.codex] == true)
    }

    @Test
    func `an older status failure cannot request a retry after newer success`() async {
        let store = Self.makeStore()
        let gate = StatusPublicationGate()
        var requests = 0
        store.startupConnectivityRetryRefreshActive = true
        store._test_providerStatusFetchOverride = { _ in
            requests += 1
            if requests == 1 {
                await gate.suspend()
                throw URLError(.notConnectedToInternet)
            }
            return Self.status(.major, description: "Current incident")
        }

        let older = Task { await store.refreshProviderStatus(.codex) }
        await gate.waitUntilStarted()
        await store.refreshProviderStatus(.codex)
        await gate.resume()
        await older.value

        #expect(store.statuses[.codex]?.description == "Current incident")
        #expect(store.startupConnectivityRetryNeeded == false)
    }

    @Test
    func `status publication ordering is independent for each provider`() async {
        let store = Self.makeStore(providers: [.codex, .claude])
        let gate = StatusPublicationGate()
        store._test_providerStatusFetchOverride = { provider in
            if provider == .codex {
                await gate.suspend()
            }
            return Self.status(.major, description: provider.rawValue)
        }

        let codex = Task { await store.refreshProviderStatus(.codex) }
        await gate.waitUntilStarted()
        await store.refreshProviderStatus(.claude)
        await gate.resume()
        await codex.value

        #expect(store.statuses[.codex]?.description == "codex")
        #expect(store.statuses[.claude]?.description == "claude")
    }

    @Test
    func `a later successful request can report a genuine recovery`() async {
        let store = Self.makeStore()
        store._test_providerStatusFetchOverride = { _ in
            Self.status(.major, description: "Incident")
        }
        await store.refreshProviderStatus(.codex)
        #expect(store.providerStatusHadIssue[.codex] == true)

        store._test_providerStatusFetchOverride = { _ in
            Self.status(.none, description: "Recovered")
        }
        await store.refreshProviderStatus(.codex)

        #expect(store.statuses[.codex]?.description == "Recovered")
        #expect(store.providerStatusHadIssue[.codex] == false)
    }

    @Test
    func `automatic refreshes reuse a healthy status until it is due`() async {
        let store = Self.makeStore()
        var requests = 0
        var indicator = ProviderStatusIndicator.none
        store._test_providerStatusFetchOverride = { _ in
            requests += 1
            return Self.status(indicator, description: "Status \(requests)")
        }

        #expect(await store.runRefresh(startupConnectivityRetryAttempt: nil))
        #expect(await store.runRefresh(startupConnectivityRetryAttempt: nil))
        #expect(requests == 1)

        // A manual refresh always rechecks the status page.
        #expect(await store.runRefresh(enrichmentMode: .forcedForeground, startupConnectivityRetryAttempt: nil))
        #expect(requests == 2)

        // An open incident is rechecked on the short interval.
        indicator = .major
        store.providerStatusPublications[.codex]?.publishedAt = Date().addingTimeInterval(-16 * 60)
        #expect(await store.runRefresh(startupConnectivityRetryAttempt: nil))
        #expect(requests == 3)
        #expect(store.statuses[.codex]?.indicator == .major)
        store.providerStatusPublications[.codex]?.publishedAt = Date().addingTimeInterval(-3 * 60)
        #expect(await store.runRefresh(startupConnectivityRetryAttempt: nil))
        #expect(requests == 4)
        await Self.drain(store)
    }

    @Test
    func `a failed status fetch retries on the next automatic refresh`() async {
        let store = Self.makeStore()
        var requests = 0
        store._test_providerStatusFetchOverride = { _ in
            requests += 1
            if requests == 1 { throw URLError(.timedOut) }
            return Self.status(.none, description: "Operational")
        }

        #expect(await store.runRefresh(startupConnectivityRetryAttempt: nil))
        #expect(await store.runRefresh(startupConnectivityRetryAttempt: nil))
        #expect(requests == 2)
        #expect(store.statuses[.codex]?.description == "Operational")
        await Self.drain(store)
    }

    private static func drain(_ store: UsageStore) async {
        store.startupConnectivityRetryTask?.cancel()
        store.startupConnectivityRetryTask = nil
        await store.creditsRefreshTask?.value
        await store.tokenRefreshSequenceTask?.value
        store.memoryPressureReliefTask?.cancel()
        await store.memoryPressureReliefTask?.value
    }

    private static func makeStore(providers: Set<UsageProvider> = [.codex]) -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "ProviderStatusRefreshPublicationTests",
            userDefaults: InMemoryUserDefaults(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        settings._test_codexAccountSnapshotLoader = { _ in
            CodexAccountReconciliationSnapshot(
                storedAccounts: [],
                activeStoredAccount: nil,
                liveSystemAccount: nil,
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: .liveSystem,
                hasUnreadableAddedAccountStore: false)
        }
        settings.providerDetectionCompleted = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = true
        settings.costUsageEnabled = false
        settings.openAIWebAccessEnabled = false
        settings.providerStorageFootprintsEnabled = false
        enableTestProviders(providers, settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store._test_providerRefreshOverride = { _ in }
        store._test_codexCreditsLoaderOverride = {
            CreditsSnapshot(remaining: 0, events: [], updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
        }
        store._test_tokenUsageRefreshOverride = { _, _ in }
        return store
    }

    private static func status(_ indicator: ProviderStatusIndicator, description: String) -> ProviderStatus {
        ProviderStatus(indicator: indicator, description: description, updatedAt: nil)
    }
}

private actor StatusPublicationGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func suspend() async {
        self.started = true
        self.startWaiter?.resume()
        self.startWaiter = nil
        await withCheckedContinuation { self.release = $0 }
    }

    func waitUntilStarted() async {
        guard !self.started else { return }
        await withCheckedContinuation { self.startWaiter = $0 }
    }

    func resume() {
        self.release?.resume()
        self.release = nil
    }
}
