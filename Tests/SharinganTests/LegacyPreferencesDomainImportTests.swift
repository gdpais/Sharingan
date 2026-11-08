import Foundation
import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct LegacyPreferencesDomainImportTests {
    @Test
    func `legacy domain maps only the app release and debug domains`() {
        #expect(LegacyPreferencesDomainImport.legacyDomain(forAppDomain: AppDefaultsDomain.release)
            == AppDefaultsDomain.legacyRelease)
        #expect(LegacyPreferencesDomainImport.legacyDomain(forAppDomain: AppDefaultsDomain.debug)
            == AppDefaultsDomain.legacyDebug)
        #expect(LegacyPreferencesDomainImport.legacyDomain(forAppDomain: AppDefaultsDomain.legacyRelease) == nil)
        #expect(LegacyPreferencesDomainImport.legacyDomain(forAppDomain: "com.gdpais.sharingan.widget") == nil)
    }

    @Test
    func `allowlisted legacy preferences are queued once and applied by the settings store`() throws {
        let legacy = InMemoryUserDefaults(values: [
            "hidePersonalInfo": true,
            "refreshFrequency": "fiveMinutes",
            "claudeOAuthKeychainPromptMode": "never",
        ])
        let appDefaults = InMemoryUserDefaults()

        #expect(LegacyPreferencesDomainImport.queueIfNeeded(into: appDefaults, legacy: legacy))
        #expect(appDefaults.bool(forKey: LegacyPreferencesDomainImport.completedKey))
        let pending = try #require(appDefaults.data(forKey: PreferencesDocument.pendingImportKey))
        let queued = try PreferencesDocument(data: pending)
        #expect(try queued.value("hidePersonalInfo", as: Bool.self) == true)
        // Non-portable (Keychain-related) keys never move.
        #expect(appDefaults.object(forKey: "claudeOAuthKeychainPromptMode") == nil)

        let settings = testSettingsStore(
            suiteName: "LegacyPreferencesDomainImportTests-apply",
            userDefaults: appDefaults)
        settings.consumePendingPreferencesImport()
        #expect(settings.hidePersonalInfo)
        #expect(settings.refreshFrequency == .fiveMinutes)
        #expect(appDefaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)

        legacy.set(false, forKey: "hidePersonalInfo")
        #expect(!LegacyPreferencesDomainImport.queueIfNeeded(into: appDefaults, legacy: legacy))
        #expect(appDefaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)
    }

    @Test
    func `missing, empty, or invalid legacy domains only mark the import complete`() {
        for legacy in [
            nil,
            InMemoryUserDefaults(),
            InMemoryUserDefaults(values: ["refreshFrequency": "notAChoice"]),
        ] as [UserDefaults?] {
            let appDefaults = InMemoryUserDefaults()
            #expect(!LegacyPreferencesDomainImport.queueIfNeeded(into: appDefaults, legacy: legacy))
            #expect(appDefaults.bool(forKey: LegacyPreferencesDomainImport.completedKey))
            #expect(appDefaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)
        }
    }
}
