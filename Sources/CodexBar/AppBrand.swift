import Foundation

/// User-facing branding for the Sharingan fork of CodexBar.
///
/// Kept in a standalone file so upstream CodexBar merges only touch the few call sites that read it.
/// Identifiers, bundle ids, paths, URL schemes, and Keychain names intentionally keep the upstream names.
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
