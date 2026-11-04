import Foundation

/// The macOS defaults domains owned by the app; they follow its bundle identifiers.
///
/// Only "this app's preferences" use these. Config folders, Keychain services, cache folders, queue labels, and log
/// subsystems keep their CodexBar names so switching apps keeps provider config and credentials.
public enum AppDefaultsDomain {
    public static let release = "com.gdpais.sharingan"
    public static let debug = "com.gdpais.sharingan.debug"
    /// Read order for helpers (e.g. the CLI) that look up the app's preferences from outside the app.
    public static let all = [release, debug]

    /// CodexBar's former domains. Read-only sources for the one-time preference import, plus the shared
    /// Claude Keychain-cache state that intentionally stays put.
    public static let legacyRelease = "com.steipete.codexbar"
    public static let legacyDebug = "com.steipete.codexbar.debug"
}
