import Foundation

/// Runtime identity of the Sharingan fork: every on-disk, defaults, Keychain, and app-group name the app owns.
///
/// Sharingan must run side by side with upstream CodexBar, so nothing it reads or writes may share a name with
/// CodexBar's (`~/.codexbar`, `~/.config/codexbar`, `com.steipete.codexbar*`, `~/Library/*/CodexBar`).
/// Swift modules, targets, and type names keep their CodexBar names to keep upstream merges cheap.
public enum AppIdentity {
    /// Reverse-DNS stem for Application Support folders, Keychain services, app groups, and log subsystems.
    public static let reverseDNS = "com.gdpais.sharingan"
    /// Folder name under Application Support, Caches, and Logs.
    public static let supportDirectoryName = "Sharingan"
    /// Folder name under `$XDG_CONFIG_HOME` / `~/.config`.
    public static let configDirectoryName = "sharingan"
    /// Hidden folder directly under the home directory (`~/.sharingan`).
    public static let homeDotDirectoryName = ".sharingan"
    /// Overrides the config file path. Deliberately not `CODEXBAR_CONFIG`, so a shell set up for CodexBar
    /// never points Sharingan at CodexBar's config.
    public static let configPathEnvironmentKey = "SHARINGAN_CONFIG"
    /// Keychain service for API tokens and cookie headers.
    public static let keychainService = "com.gdpais.sharingan"
    /// Keychain service for cached OAuth credentials and other cache items.
    public static let keychainCacheService = "com.gdpais.sharingan.cache"
    public static let keychainCacheLabel = "Sharingan Cache"
    /// CloudKit container. iCloud sync stays unavailable until this container is provisioned for the bundle.
    public static let iCloudContainerIdentifier = "iCloud.com.gdpais.sharingan"
    /// Name of the CLI symlink the app installs into `/usr/local/bin` or `/opt/homebrew/bin`.
    public static let cliCommandName = "sharingan"
}
