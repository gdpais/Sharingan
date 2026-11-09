import Foundation
import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct HideProjectInfoSettingsTests {
    @Test
    func `hiding personal info hides project names by default`() {
        let settings = self.makeSettingsStore(suite: "HideProjectInfoSettingsTests-default")
        #expect(settings.hideProjectInfo == false)

        settings.hidePersonalInfo = true

        #expect(settings.showProjectNamesWhenHidingPersonalInfo == false)
        #expect(settings.hideProjectInfo)
    }

    @Test
    func `keeping project names visible only unmasks projects`() {
        let settings = self.makeSettingsStore(suite: "HideProjectInfoSettingsTests-keep-projects")
        settings.hidePersonalInfo = true
        settings.showProjectNamesWhenHidingPersonalInfo = true

        #expect(settings.hidePersonalInfo)
        #expect(settings.hideProjectInfo == false)
    }

    @Test
    func `project names stay visible when personal info is shown`() {
        let settings = self.makeSettingsStore(suite: "HideProjectInfoSettingsTests-shown")
        settings.showProjectNamesWhenHidingPersonalInfo = true

        #expect(settings.hideProjectInfo == false)
    }

    @Test
    func `keep project names choice persists`() {
        let suite = "HideProjectInfoSettingsTests-persist"
        let settings = self.makeSettingsStore(suite: suite)
        settings.hidePersonalInfo = true
        settings.showProjectNamesWhenHidingPersonalInfo = true

        let reloaded = self.makeSettingsStore(suite: suite, reset: false)

        #expect(reloaded.showProjectNamesWhenHidingPersonalInfo)
        #expect(reloaded.hideProjectInfo == false)
    }

    @Test
    func `project identity follows the project info flag`() {
        let shown = CostHistoryIdentity(name: "sharingan", path: "/tmp/sharingan", placeholder: "Project 1",
                                        hidePersonalInfo: false)
        let hidden = CostHistoryIdentity(name: "sharingan", path: "/tmp/sharingan", placeholder: "Project 1",
                                         hidePersonalInfo: true)

        #expect(shown.name == "sharingan")
        #expect(shown.path == "/tmp/sharingan")
        #expect(hidden.name == "Project 1")
        #expect(hidden.path == nil)
    }

    private func makeSettingsStore(suite: String, reset: Bool = true) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        if reset {
            defaults.removePersistentDomain(forName: suite)
        }
        return SettingsStore(
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
    }
}
