import CodexBarCore

extension UsageStore {
    /// Hands the widget the user's severity bands so its lanes classify like the menu. Untouched
    /// settings write nothing, keeping the snapshot as it was and the widget on the standard bands.
    func widgetEntryWithSeverityBands(_ entry: WidgetSnapshot.ProviderEntry) -> WidgetSnapshot.ProviderEntry {
        guard let provider = entry.provider.firstPartyProvider else { return entry }
        let bands = self.settings.quotaSeverityBandSet(for: provider)
        var entry = entry
        entry.severityBands = bands.isStandard ? nil : bands
        return entry
    }

    func widgetAccountWithSeverityBands(_ account: WidgetSnapshot.AccountEntry) -> WidgetSnapshot.AccountEntry {
        guard let usage = account.usage else { return account }
        return WidgetSnapshot.AccountEntry(
            id: account.id,
            provider: account.provider,
            label: account.label,
            usage: self.widgetEntryWithSeverityBands(usage))
    }
}
