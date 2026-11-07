import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ProviderSpendPlanTests {
    // MARK: - Shared config

    @Test
    func `spend plans round trip through the shared config`() throws {
        var provider = ProviderConfig(id: .claude, enabled: true)
        provider.spendPlan = ProviderSpendPlan(planMonthlyPrice: 200, monthlyBudget: 49.5, currencyCode: "EUR")
        let data = try CodexBarConfig(providers: [provider]).encodedData()

        let decoded = try CodexBarConfig.decode(from: data)
        #expect(decoded.providerConfig(for: .claude)?.spendPlan == ProviderSpendPlan(
            planMonthlyPrice: 200,
            monthlyBudget: 49.5,
            currencyCode: "EUR"))
        let plan = try Self.spendPlanObject(in: data)
        #expect(plan["planMonthlyPrice"] as? Double == 200)
        #expect(plan["monthlyBudget"] as? Double == 49.5)
        #expect(plan["currencyCode"] as? String == "EUR")
    }

    /// Readers that know only the generic provider keys decode `spendPlan` as an opaque extension value
    /// and write it back as read, which is what keeps the numbers alive across their rewrites.
    @Test
    func `a rewrite that never reads the plan keeps it byte for byte`() throws {
        let json = #"{"version":1,"providers":[{"id":"codex","enabled":true,"spendPlan":"#
            + #"{"planMonthlyPrice":20,"monthlyBudget":12.75,"currencyCode":"USD","futureKey":true}}]}"#
        var config = try CodexBarConfig.decode(from: Data(json.utf8))
        var codex = try #require(config.providerConfig(for: .codex))
        codex.enabled = false
        config.setProviderConfig(codex)

        let rewritten = try config.encodedData()
        let plan = try Self.spendPlanObject(in: rewritten)
        #expect(plan["planMonthlyPrice"] as? Double == 20)
        #expect(plan["monthlyBudget"] as? Double == 12.75)
        #expect(plan["futureKey"] as? Bool == true)
        #expect(try CodexBarConfig.decode(from: rewritten).providerConfig(for: .codex)?.enabled == false)
    }

    @Test
    func `configs without a spend plan read and write as before`() throws {
        let json = #"{"version":1,"providers":[{"id":"codex","enabled":true}]}"#
        let config = try CodexBarConfig.decode(from: Data(json.utf8))
        #expect(config.providerConfig(for: .codex)?.spendPlan == nil)
        let text = try #require(String(bytes: config.encodedData(), encoding: .utf8))
        #expect(!text.contains("spendPlan"))
    }

    @Test
    func `hand edited values that do not parse are dropped field by field`() throws {
        let json = #"{"version":1,"providers":[{"id":"claude","spendPlan":"#
            + #"{"planMonthlyPrice":"twenty","monthlyBudget":30,"currencyCode":42}}]}"#
        let plan = try #require(CodexBarConfig.decode(from: Data(json.utf8)).providerConfig(for: .claude)?.spendPlan)
        #expect(plan.planMonthlyPrice == nil)
        #expect(plan.validMonthlyBudget == 30)
        #expect(plan.currencyCode == nil)
        #expect(plan.resolvedCurrencyCode(fallback: "gbp") == "GBP")
        #expect(plan.resolvedCurrencyCode(fallback: nil) == "USD")

        for value in [#"{"monthlyBudget":-5}"#, #""lots""#, #"{"currencyCode":"EUR"}"#] {
            let edited = #"{"version":1,"providers":[{"id":"claude","spendPlan":"# + value + "}]}"
            #expect(try CodexBarConfig.decode(from: Data(edited.utf8)).providerConfig(for: .claude)?.spendPlan == nil)
        }
    }

    @Test
    func `clearing every amount removes the key`() throws {
        var provider = ProviderConfig(id: .codex)
        provider.spendPlan = ProviderSpendPlan(monthlyBudget: 10, currencyCode: "USD")
        provider.spendPlan = ProviderSpendPlan(currencyCode: "USD")
        #expect(provider.spendPlan == nil)
        let text = try #require(String(bytes: CodexBarConfig(providers: [provider]).encodedData(), encoding: .utf8))
        #expect(!text.contains("spendPlan"))
    }

    @Test
    func `the plan is a display preference that never changes fetch identity`() throws {
        var provider = ProviderConfig(id: .claude, enabled: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let identity = try encoder.encode(provider.fetchIdentityConfig)
        provider.spendPlan = ProviderSpendPlan(planMonthlyPrice: 100, monthlyBudget: 20, currencyCode: "USD")
        #expect(try encoder.encode(provider.fetchIdentityConfig) == identity)
    }

    // MARK: - Amounts

    @Test
    func `amounts outside the accepted range are not usable`() {
        for value in [0, -1, Double.nan, Double.infinity, 1_000_001] {
            #expect(ProviderSpendPlan.validAmount(value) == nil)
        }
        #expect(ProviderSpendPlan.validAmount(0.01) == 0.01)
        #expect(ProviderSpendPlan.validAmount(1_000_000) == 1_000_000)
        #expect(ProviderSpendPlan(currencyCode: "USD").isEmpty)
        #expect(ProviderSpendPlan.normalizedCurrencyCode(" eur ") == "EUR")
        #expect(ProviderSpendPlan.normalizedCurrencyCode("EURO") == nil)
        #expect(ProviderSpendPlan.normalizedCurrencyCode("€") == nil)
    }

    @Test
    func `typed amounts parse with either separator`() {
        let cases: [(text: String, decimalSeparator: String, expected: Double)] = [
            ("200", ".", 200),
            ("19.99", ".", 19.99),
            ("19,99", ".", 19.99),
            ("19,99", ",", 19.99),
            ("1,200", ".", 1200),
            ("1,200", ",", 1.2),
            ("1.200", ",", 1200),
            ("$1,200.50", ".", 1200.5),
            ("1.200,50 €", ",", 1200.5),
            ("1.234.567", ".", 1_234_567),
        ]
        for item in cases {
            #expect(ProviderSpendPlan.parseAmount(item.text, decimalSeparator: item.decimalSeparator) == item.expected)
        }
        #expect(ProviderSpendPlan.parseAmount("abc") == nil)
        #expect(ProviderSpendPlan.parseAmount("-") == nil)
    }

    @Test
    func `amount text rejects what is not a positive amount`() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        #expect(SpendPlanAmountText.parse("  ", locale: english) == .empty)
        #expect(SpendPlanAmountText.parse("abc", locale: english) == .invalid)
        #expect(SpendPlanAmountText.parse("0", locale: english) == .invalid)
        #expect(SpendPlanAmountText.parse("-20", locale: english) == .invalid)
        #expect(SpendPlanAmountText.parse("2000000", locale: english) == .invalid)
        #expect(SpendPlanAmountText.parse("19,99", locale: german) == .amount(19.99))
        #expect(SpendPlanAmountText.text(for: 1200.5, locale: english) == "1200.5")
        #expect(SpendPlanAmountText.text(for: 19.99, locale: german) == "19,99")
        #expect(SpendPlanAmountText.text(for: nil, locale: english).isEmpty)
    }

    private static func spendPlanObject(in data: Data) throws -> [String: Any] {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let providers = try #require(object["providers"] as? [[String: Any]])
        return try #require(providers.first?["spendPlan"] as? [String: Any])
    }
}

@MainActor
struct SpendPlanSettingsTests {
    @Test
    func `setting a plan round trips and leaves the provider refresh revision alone`() {
        let settings = testSettingsStore(suiteName: "SpendPlanSettingsTests-roundTrip")
        let before = settings.providerConfigRevision(for: .claude)
        #expect(settings.spendPlansByProvider.isEmpty)
        #expect(!settings.hasAnySpendBudget)

        settings.setSpendPlan(
            ProviderSpendPlan(planMonthlyPrice: 100, monthlyBudget: 40, currencyCode: "USD"),
            for: .claude)
        #expect(settings.spendPlan(for: .claude)?.validMonthlyBudget == 40)
        #expect(settings.spendPlansByProvider[.claude]?.validPlanMonthlyPrice == 100)
        #expect(settings.hasAnySpendBudget)
        #expect(settings.providerConfigRevision(for: .claude) == before)

        settings.setSpendPlan(ProviderSpendPlan(currencyCode: "USD"), for: .claude)
        #expect(settings.spendPlan(for: .claude) == nil)
        #expect(!settings.hasAnySpendBudget)
    }

    @Test
    func `budget alerts default on and their state persists per provider`() {
        let settings = testSettingsStore(suiteName: "SpendPlanSettingsTests-alerts")
        #expect(settings.spendBudgetNotificationsEnabled)
        settings.spendBudgetNotificationsEnabled = false
        #expect(!settings.spendBudgetNotificationsEnabled)

        let state = SpendBudgetAlertState(monthKey: "2026-11", budget: 50, currencyCode: "USD", announcedPercents: [80])
        settings.setSpendBudgetAlertState(state, for: .claude)
        #expect(settings.spendBudgetAlertState(for: .claude) == state)
        #expect(settings.spendBudgetAlertState(for: .codex) == nil)
        settings.setSpendBudgetAlertState(nil, for: .claude)
        #expect(settings.spendBudgetAlertState(for: .claude) == nil)
    }

    @Test
    func `budget hook rules stay out of the shared config`() {
        let settings = testSettingsStore(suiteName: "SpendPlanSettingsTests-hooks")
        settings.spendBudgetHookRules = [
            HookRule(id: "budget", event: .budgetReached, provider: "claude", executable: "/usr/bin/true"),
            HookRule(id: "quota", event: .quotaLow, executable: "/usr/bin/true"),
        ]
        #expect(settings.spendBudgetHookRules.map(\.id) == ["budget"])
        #expect(settings.configSnapshot.hooks == nil)
        settings.spendBudgetHookRules = []
        #expect(settings.spendBudgetHookRules.isEmpty)
    }
}
