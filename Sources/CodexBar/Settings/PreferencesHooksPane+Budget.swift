import CodexBarCore
import SwiftUI

/// Budget hooks in the Hooks pane: `budget_reached` rules, kept in this app's preferences rather than
/// the shared config file (see `HookEventType.sharedConfigCases`). They run only while hooks are enabled.
@MainActor
struct BudgetHookRulesSection: View {
    @Bindable var settings: SettingsStore
    @State private var rules: [HookRule]

    init(settings: SettingsStore) {
        self.settings = settings
        self._rules = State(initialValue: settings.spendBudgetHookRules)
    }

    var body: some View {
        Section {
            if self.rules.isEmpty {
                Text(L("hooks_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(self.rules) { rule in
                    BudgetHookRuleRow(
                        rule: self.binding(for: rule),
                        onDelete: { self.rules.removeAll { $0.id == rule.id } })
                }
            }

            Button {
                self.rules.append(HookRule(event: .budgetReached, executable: ""))
            } label: {
                Label(L("budget_hooks_add_rule"), systemImage: "plus")
            }
            .disabled(!HookEditorValidation.canAddRule(count: self.rules.count))
        } header: {
            Text(L("budget_hooks_header"))
        } footer: {
            SettingsSectionFooter(L("budget_hooks_footer"))
        }
        .onChange(of: self.rules) { _, rules in
            self.settings.spendBudgetHookRules = rules
        }
    }

    private func binding(for rule: HookRule) -> Binding<HookRule> {
        Binding(
            get: { self.rules.first(where: { $0.id == rule.id }) ?? rule },
            set: { updated in
                guard let index = self.rules.firstIndex(where: { $0.id == updated.id }) else { return }
                self.rules[index] = updated
            })
    }
}

/// One budget hook: on/off, provider scope, executable and arguments. The event is fixed.
@MainActor
private struct BudgetHookRuleRow: View {
    @Binding var rule: HookRule
    let onDelete: () -> Void
    @State private var argumentRows: [ArgumentRow]

    init(rule: Binding<HookRule>, onDelete: @escaping () -> Void) {
        self._rule = rule
        self.onDelete = onDelete
        self._argumentRows = State(initialValue: rule.wrappedValue.arguments.map(ArgumentRow.init(value:)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(L("hooks_rule_enabled"), isOn: self.$rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Text(verbatim: HookEventType.budgetReached.rawValue)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Picker(L("hooks_provider"), selection: self.providerBinding) {
                    Text(L("hooks_any_provider")).tag(String?.none)
                    ForEach(Self.costProviders, id: \.self) { provider in
                        Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName)
                            .tag(String?.some(provider.rawValue))
                    }
                }
                .labelsHidden()

                Spacer()

                Button(role: .destructive, action: self.onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("hooks_delete_rule"))
            }

            TextField(
                L("hooks_executable"),
                text: self.$rule.executable,
                prompt: Text(L("hooks_executable_placeholder")))
                .labelsHidden()
                .accessibilityLabel(L("hooks_executable"))
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("hooks_arguments_placeholder"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        self.argumentRows.append(ArgumentRow(value: ""))
                    } label: {
                        Label(L("hooks_add_argument"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!HookEditorValidation.canAddArgument(count: self.argumentRows.count))
                }

                ForEach(self.$argumentRows) { $argument in
                    HStack {
                        TextField(
                            L("hooks_argument_placeholder"),
                            text: $argument.value,
                            prompt: Text(L("hooks_argument_placeholder")))
                            .labelsHidden()
                            .accessibilityLabel(L("hooks_argument_placeholder"))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            self.argumentRows.removeAll(where: { $0.id == argument.id })
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("hooks_delete_argument"))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: self.argumentRows.map(\.value)) { _, arguments in
            if self.rule.arguments != arguments {
                self.rule.arguments = arguments
            }
        }
    }

    /// Budgets compare against cost history, so only providers that keep one are offered.
    private static var costProviders: [UsageProvider] {
        UsageProvider.allCases.filter { ProviderDescriptorRegistry.descriptor(for: $0).tokenCost.supportsTokenCost }
    }

    private var providerBinding: Binding<String?> {
        Binding(get: { self.rule.provider }, set: { self.rule.provider = $0 })
    }

    private struct ArgumentRow: Identifiable {
        let id = UUID()
        var value: String
    }
}
