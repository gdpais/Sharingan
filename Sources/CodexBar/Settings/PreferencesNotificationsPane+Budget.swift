import SwiftUI

/// Budget alerts toggle for the Notifications pane.
///
/// No provider has a budget by default, so the toggle reads off and stays disabled until one does; from
/// then on it defaults to on. The choice lives in this app's defaults, outside observation, so the view
/// keeps its own copy of it.
@MainActor
struct BudgetAlertNotificationToggle: View {
    @Bindable var settings: SettingsStore
    @State private var isEnabled: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        self._isEnabled = State(initialValue: settings.spendBudgetNotificationsEnabled)
    }

    var body: some View {
        let hasBudget = self.settings.hasAnySpendBudget
        Toggle(isOn: self.enabledBinding(hasBudget: hasBudget)) {
            SettingsRowLabel(
                L("budget_notifications_title"),
                subtitle: hasBudget ? L("budget_notifications_subtitle") : L("budget_notifications_no_budget"))
        }
        .disabled(!hasBudget)
    }

    private func enabledBinding(hasBudget: Bool) -> Binding<Bool> {
        Binding(
            get: { hasBudget && self.isEnabled },
            set: { enabled in
                self.isEnabled = enabled
                self.settings.spendBudgetNotificationsEnabled = enabled
            })
    }
}
