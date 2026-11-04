import Foundation
import Testing
@testable import CodexBarCore

struct AppDefaultsDomainTests {
    @Test
    func `app defaults domains follow the Sharingan bundle identifiers`() {
        #expect(AppDefaultsDomain.release == "com.gdpais.sharingan")
        #expect(AppDefaultsDomain.debug == "com.gdpais.sharingan.debug")
        #expect(AppDefaultsDomain.all == ["com.gdpais.sharingan", "com.gdpais.sharingan.debug"])
        #expect(AppDefaultsDomain.legacyRelease == "com.steipete.codexbar")
        #expect(AppDefaultsDomain.legacyDebug == "com.steipete.codexbar.debug")
    }

    @Test
    func `portable preferences target the app defaults domain`() {
        #expect(PreferencesDocument.defaultsDomain == AppDefaultsDomain.release)
        #expect(PreferencesDocument.importNotification == "com.gdpais.sharingan.preferencesImport")
    }

    @Test
    func `Claude prompt mode reads the app defaults domains`() {
        #expect(ClaudeOAuthKeychainPromptPreference.releaseApplicationDefaultsDomain == AppDefaultsDomain.release)
        #expect(ClaudeOAuthKeychainPromptPreference.debugApplicationDefaultsDomain == AppDefaultsDomain.debug)

        let release = ClaudeOAuthKeychainPromptPreference.resolveApplicationDefaultsDomain(
            bundleIdentifier: "com.gdpais.sharingan.widget",
            bundleURL: nil,
            executableURL: nil,
            invocationURL: nil)
        #expect(release == AppDefaultsDomain.release)

        // A CodexBar bundle identifier is no longer this app's domain; it falls back to the release default.
        let legacy = ClaudeOAuthKeychainPromptPreference.resolveApplicationDefaultsDomain(
            bundleIdentifier: AppDefaultsDomain.legacyDebug,
            bundleURL: nil,
            executableURL: nil,
            invocationURL: nil,
            bundleIdentifierForApp: { _ in nil })
        #expect(legacy == AppDefaultsDomain.release)
    }
}
