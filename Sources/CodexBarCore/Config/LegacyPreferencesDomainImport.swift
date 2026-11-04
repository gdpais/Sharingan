import Foundation

/// One-time carry-over of portable display preferences from CodexBar's defaults domain into this app's domain.
///
/// Only the `PreferencesDocument` allowlist moves (UI/display choices); provider config, credentials, and Keychain
/// settings are never read. The values are queued through the existing pending-import key, so the app applies them
/// with its normal setters. The legacy domain is only read, never modified.
public enum LegacyPreferencesDomainImport {
    public static let completedKey = "legacyCodexBarPreferencesImportCompleted"

    /// The CodexBar domain matching this app's release or debug domain, or nil for any other bundle identifier.
    public static func legacyDomain(forAppDomain domain: String) -> String? {
        switch domain {
        case AppDefaultsDomain.release: AppDefaultsDomain.legacyRelease
        case AppDefaultsDomain.debug: AppDefaultsDomain.legacyDebug
        default: nil
        }
    }

    /// Queues the legacy preferences once. Returns true when something was queued.
    @discardableResult
    public static func queueIfNeeded(into appDefaults: UserDefaults, legacy: UserDefaults?) -> Bool {
        guard !appDefaults.bool(forKey: self.completedKey) else { return false }
        // Mark first so an unreadable or invalid legacy domain is not retried on every launch.
        appDefaults.set(true, forKey: self.completedKey)
        guard let legacy,
              let document = try? PreferencesDocument(defaults: legacy),
              !document.isEmpty
        else { return false }
        do {
            try document.queueImport(in: appDefaults)
            return true
        } catch {
            return false
        }
    }
}
