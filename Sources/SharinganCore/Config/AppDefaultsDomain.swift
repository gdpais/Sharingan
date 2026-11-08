import Foundation

/// The macOS defaults domains owned by the app; they follow its bundle identifiers.
///
/// Only "this app's preferences" use these. Config folders, Keychain services, and cache folders follow
/// `AppIdentity`, so Sharingan and CodexBar can run side by side without sharing state.
public enum AppDefaultsDomain {
    public static let release = "com.gdpais.sharingan"
    public static let debug = "com.gdpais.sharingan.debug"
    /// Read order for helpers (e.g. the CLI) that look up the app's preferences from outside the app.
    public static let all = [release, debug]

    /// Upstream CodexBar's domains. Read-only source for the one-time preference import; never written.
    public static let legacyRelease = "com.steipete.codexbar"
    public static let legacyDebug = "com.steipete.codexbar.debug"
}
