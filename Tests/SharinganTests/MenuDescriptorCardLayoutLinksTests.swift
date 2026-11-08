import Foundation
import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct MenuDescriptorCardLayoutLinksTests {
    @Test
    func `usage dashboard and status page stay in the menu by default`() {
        let settings = Self.settings()
        let titles = Self.actionTitles(provider: .codex, settings: settings)
        #expect(titles.contains("Usage Dashboard"))
        #expect(titles.contains("Status Page"))
    }

    @Test
    func `each link can be hidden per provider`() {
        let settings = Self.settings()
        settings.updateMenuCardLayout(for: .codex) { $0.setMenuItem(.statusPage, visible: false) }
        settings.updateMenuCardLayout(for: .claude) { $0.setMenuItem(.usageDashboard, visible: false) }

        let codex = Self.actionTitles(provider: .codex, settings: settings)
        #expect(codex.contains("Usage Dashboard"))
        #expect(!codex.contains("Status Page"))

        let claude = Self.actionTitles(provider: .claude, settings: settings)
        #expect(!claude.contains("Usage Dashboard"))
        #expect(claude.contains("Status Page"))
    }

    private static func settings() -> SettingsStore {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        return settings
    }

    private static func actionTitles(provider: UsageProvider, settings: SettingsStore) -> [String] {
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let descriptor = MenuDescriptor.build(
            provider: provider,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: true)
        return descriptor.sections
            .flatMap(\.entries)
            .compactMap { entry -> String? in
                guard case let .action(title, _) = entry else { return nil }
                return title
            }
    }
}
