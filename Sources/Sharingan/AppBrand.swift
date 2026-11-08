import Foundation

/// User-facing branding for the Sharingan fork of CodexBar.
///
/// Runtime identifiers (paths, defaults, Keychain, app group) live in `AppIdentity` so Sharingan never shares
/// state with a CodexBar install. The `upstream*` values credit the original project and must stay as they are.
enum AppBrand {
    static let displayName = "Sharingan"
    static let repositoryURL = "https://github.com/gdpais/Sharingan"
    static let readmeURL = "https://github.com/gdpais/Sharingan/blob/main/README.md"

    static let upstreamName = "CodexBar"
    static let upstreamAuthor = "Peter Steinberger"
    static let upstreamRepositoryURL = "https://github.com/steipete/CodexBar"
    /// Localization key whose English text doubles as the fallback when no catalog entry exists yet.
    static let upstreamCreditKey = "Based on CodexBar by Peter Steinberger"
}
