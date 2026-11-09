import Foundation
import SharinganCore

extension UsageStore {
    /// Minimum spacing between menu-open Claude repairs, so reopening the menu cannot relaunch the
    /// `claude` CLI (and any Keychain prompt it shows) on every open.
    static let claudeMenuOpenRepairInterval: TimeInterval = 60

    /// Interaction to use when the open menu retries `provider`. Opening the menu is a user action, so a Claude
    /// token repair deferred by the "only on user action" Keychain policy runs user-initiated here instead of
    /// failing again in the background. Everything else keeps the background interaction.
    func menuOpenRetryInteraction(for provider: UsageProvider, now: Date = Date()) -> ProviderInteraction {
        guard provider == .claude,
              let error = self.errors[provider.instanceID],
              ClaudeUsageError.isUserActionRepairRequiredDescription(error)
        else { return .background }
        if let last = self.lastClaudeMenuOpenRepairAt,
           now.timeIntervalSince(last) < Self.claudeMenuOpenRepairInterval
        {
            return .background
        }
        self.lastClaudeMenuOpenRepairAt = now
        return .userInitiated
    }
}
