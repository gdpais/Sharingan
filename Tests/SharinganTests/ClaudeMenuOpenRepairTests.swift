import Foundation
import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct ClaudeMenuOpenRepairTests {
    private static let deferredRepairError =
        "Claude OAuth token expired, but background repair is suppressed when Keychain prompt policy "
            + "is set to only prompt on user action. Click Refresh in the Sharingan menu to retry."

    @Test
    func `deferred claude repair retries user initiated on menu open`() {
        let store = self.makeUsageStore(suite: "ClaudeMenuOpenRepairTests-deferred")
        store.errors[.claude] = Self.deferredRepairError

        #expect(store.menuOpenRetryInteraction(for: .claude) == .userInitiated)
    }

    @Test
    func `menu open repair is throttled between opens`() {
        let store = self.makeUsageStore(suite: "ClaudeMenuOpenRepairTests-throttle")
        store.errors[.claude] = Self.deferredRepairError
        let start = Date(timeIntervalSince1970: 1_000_000)

        #expect(store.menuOpenRetryInteraction(for: .claude, now: start) == .userInitiated)
        #expect(store.menuOpenRetryInteraction(for: .claude, now: start.addingTimeInterval(10)) == .background)
        let afterInterval = start.addingTimeInterval(UsageStore.claudeMenuOpenRepairInterval)
        #expect(store.menuOpenRetryInteraction(for: .claude, now: afterInterval) == .userInitiated)
    }

    @Test
    func `other claude errors keep background retry`() {
        let store = self.makeUsageStore(suite: "ClaudeMenuOpenRepairTests-other-error")
        store.errors[.claude] = "Claude usage is temporarily unavailable."

        #expect(store.menuOpenRetryInteraction(for: .claude) == .background)
    }

    @Test
    func `other providers keep background retry`() {
        let store = self.makeUsageStore(suite: "ClaudeMenuOpenRepairTests-other-provider")
        store.errors[.codex] = Self.deferredRepairError

        #expect(store.menuOpenRetryInteraction(for: .codex) == .background)
    }

    @Test
    func `healthy claude keeps background retry`() {
        let store = self.makeUsageStore(suite: "ClaudeMenuOpenRepairTests-healthy")

        #expect(store.menuOpenRetryInteraction(for: .claude) == .background)
    }

    private func makeUsageStore(suite: String) -> UsageStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
    }
}
