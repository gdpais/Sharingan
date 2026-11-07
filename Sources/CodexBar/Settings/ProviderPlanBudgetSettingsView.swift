import CodexBarCore
import SwiftUI

/// Plan & budget: the user's own monthly plan price and monthly budget for one provider.
///
/// Both start empty, which keeps every surface as it was. The plan price feeds plan value in Usage &
/// Spend; the budget adds a budget line to the cost history chart and drives budget alerts and the
/// `budget_reached` hook. Shown only for providers with cost history, since both compare against it.
@MainActor
struct ProviderPlanBudgetSettingsView: View {
    private enum Field: Hashable {
        case price
        case budget
    }

    private static let amountFieldWidth: CGFloat = 96

    let provider: UsageProvider
    @Bindable var store: UsageStore

    @State private var priceText: String
    @State private var budgetText: String
    @State private var currencyCode: String
    @State private var invalidFields: Set<Field> = []
    @FocusState private var focusedField: Field?

    init(provider: UsageProvider, store: UsageStore) {
        self.provider = provider
        self.store = store
        let plan = store.settings.spendPlan(for: provider)
        self._priceText = State(initialValue: SpendPlanAmountText.text(for: plan?.validPlanMonthlyPrice))
        self._budgetText = State(initialValue: SpendPlanAmountText.text(for: plan?.validMonthlyBudget))
        self._currencyCode = State(initialValue: Self.resolvedCurrency(plan: plan, provider: provider, store: store))
    }

    var body: some View {
        if ProviderDescriptorRegistry.descriptor(for: self.provider).tokenCost.supportsTokenCost {
            Section {
                self.amountRow(.price, title: L("Plan price"), subtitle: L("plan_price_subtitle"))
                self.amountRow(.budget, title: L("Monthly budget"), subtitle: L("monthly_budget_subtitle"))
                SettingsMenuPicker(
                    selection: self.currencyBinding,
                    options: self.currencyOptions,
                    label: {
                        SettingsRowLabel(L("Currency"))
                    },
                    optionLabel: { code in
                        Text(verbatim: PreferredCurrencyOption.label(for: code))
                    })
            } header: {
                Text(L("Plan & budget"))
            } footer: {
                SettingsSectionFooter(L("plan_budget_footer"))
            }
            .background(FocusResigningBackground())
            .onChange(of: self.focusedField) { previous, _ in
                if let previous {
                    self.commit(previous)
                }
            }
            .onChange(of: self.store.settings.configRevision) { _, _ in
                // An external config edit can change the plan while this pane is open; never fight a
                // field the user is typing in.
                guard self.focusedField == nil else { return }
                self.syncFromSettings()
            }
            .onDisappear {
                self.commit(.price)
                self.commit(.budget)
            }
        }
    }

    // MARK: - Rows

    private func amountRow(_ field: Field, title: String, subtitle: String) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField(title, text: self.textBinding(field), prompt: Text(verbatim: field == .price ? "20" : "100"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: Self.amountFieldWidth)
                    .focused(self.$focusedField, equals: field)
                    .onSubmit { self.commit(field) }
                    .accessibilityLabel(title)
                Text(verbatim: self.currencyCode)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if self.storedAmount(field) != nil {
                    Button(L("Clear")) { self.clear(field) }
                        .controlSize(.small)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                SettingsRowLabel(title, subtitle: subtitle)
                if self.invalidFields.contains(field) {
                    Text(L("plan_budget_invalid_amount"))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var currencyOptions: [String] {
        let supported = CurrencyExchange.supportedCurrencies
        return supported.contains(self.currencyCode) ? supported : [self.currencyCode] + supported
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { self.currencyCode },
            set: { code in
                self.currencyCode = code
                guard var plan = self.store.settings.spendPlan(for: self.provider) else { return }
                plan.currencyCode = code
                self.store.settings.setSpendPlan(plan, for: self.provider)
            })
    }

    private func textBinding(_ field: Field) -> Binding<String> {
        Binding(
            get: { field == .price ? self.priceText : self.budgetText },
            set: { text in
                self.invalidFields.remove(field)
                if field == .price {
                    self.priceText = text
                } else {
                    self.budgetText = text
                }
            })
    }

    // MARK: - Persistence

    private func storedAmount(_ field: Field) -> Double? {
        let plan = self.store.settings.spendPlan(for: self.provider)
        return field == .price ? plan?.validPlanMonthlyPrice : plan?.validMonthlyBudget
    }

    /// Saves a valid amount, clears the value for empty text, and flags anything else without saving.
    private func commit(_ field: Field) {
        let text = field == .price ? self.priceText : self.budgetText
        switch SpendPlanAmountText.parse(text) {
        case .empty:
            self.invalidFields.remove(field)
            self.save(nil, for: field)
        case let .amount(amount):
            self.invalidFields.remove(field)
            self.save(amount, for: field)
            self.setText(SpendPlanAmountText.text(for: amount), for: field)
        case .invalid:
            self.invalidFields.insert(field)
        }
    }

    private func clear(_ field: Field) {
        self.invalidFields.remove(field)
        self.setText("", for: field)
        self.save(nil, for: field)
    }

    private func save(_ amount: Double?, for field: Field) {
        var plan = self.store.settings.spendPlan(for: self.provider) ?? ProviderSpendPlan()
        guard (field == .price ? plan.validPlanMonthlyPrice : plan.validMonthlyBudget) != amount else { return }
        switch field {
        case .price: plan.planMonthlyPrice = amount
        case .budget: plan.monthlyBudget = amount
        }
        plan.currencyCode = self.currencyCode
        self.store.settings.setSpendPlan(plan, for: self.provider)
    }

    private func setText(_ text: String, for field: Field) {
        switch field {
        case .price: self.priceText = text
        case .budget: self.budgetText = text
        }
    }

    private func syncFromSettings() {
        let plan = self.store.settings.spendPlan(for: self.provider)
        if !self.invalidFields.contains(.price) {
            self.priceText = SpendPlanAmountText.text(for: plan?.validPlanMonthlyPrice)
        }
        if !self.invalidFields.contains(.budget) {
            self.budgetText = SpendPlanAmountText.text(for: plan?.validMonthlyBudget)
        }
        if plan != nil {
            self.currencyCode = Self.resolvedCurrency(plan: plan, provider: self.provider, store: self.store)
        }
    }

    /// The stored currency, else the provider's cost currency, else USD.
    private static func resolvedCurrency(
        plan: ProviderSpendPlan?,
        provider: UsageProvider,
        store: UsageStore) -> String
    {
        let costCurrency = store.spendBudgetTokenSnapshot(for: provider)?.currencyCode
        return (plan ?? ProviderSpendPlan()).resolvedCurrencyCode(fallback: costCurrency)
    }
}

/// Text for the plan and budget amount fields, kept pure so parsing and formatting can be tested.
enum SpendPlanAmountText {
    enum Parsed: Equatable {
        case empty
        case amount(Double)
        case invalid
    }

    static func parse(_ text: String, locale: Locale = codexBarLocalizedLocale()) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        // Saved at the field's own precision (cents), so the text shown after a save parses back to the stored
        // amount instead of drifting on the next commit.
        guard let value = ProviderSpendPlan.parseAmount(trimmed, decimalSeparator: locale.decimalSeparator ?? "."),
              value.isFinite,
              let amount = ProviderSpendPlan.validAmount((value * 100).rounded() / 100)
        else { return .invalid }
        return .amount(amount)
    }

    static func text(for amount: Double?, locale: Locale = codexBarLocalizedLocale()) -> String {
        guard let amount else { return "" }
        return amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }
}
