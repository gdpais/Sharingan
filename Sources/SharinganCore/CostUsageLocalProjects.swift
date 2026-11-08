import Foundation

extension UsageProvider {
    /// Whether the local cost scanner attributes this provider's usage to working-directory projects, so cost
    /// surfaces may show the token snapshot's project rows.
    public var supportsLocalProjects: Bool {
        // Provider-specific by design: only Codex and Claude Code transcripts record a session working directory.
        self == .codex || self == .claude
    }
}
