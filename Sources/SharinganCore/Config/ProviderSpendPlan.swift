import Foundation

/// The user's own numbers for one provider: what its plan costs per month and how much a month's spend may
/// reach. Both are optional and absent by default, which keeps every surface as it was.
///
/// Stored in Sharingan's config as the provider key `spendPlan`.
public struct ProviderSpendPlan: Codable, Sendable, Equatable {
    /// Largest amount the editor accepts, matching the menu bar's cost thresholds.
    public static let maximumAmount = 1_000_000.0
    public static let fallbackCurrencyCode = "USD"

    /// Monthly subscription price, compared with API-equivalent spend as plan value.
    public var planMonthlyPrice: Double?
    /// Monthly spend budget, compared with estimated month-to-date spend.
    public var monthlyBudget: Double?
    /// ISO 4217 code for both amounts. `nil` reads as the provider's cost currency.
    public var currencyCode: String?

    private enum CodingKeys: String, CodingKey {
        case planMonthlyPrice
        case monthlyBudget
        case currencyCode
    }

    public init(planMonthlyPrice: Double? = nil, monthlyBudget: Double? = nil, currencyCode: String? = nil) {
        self.planMonthlyPrice = planMonthlyPrice
        self.monthlyBudget = monthlyBudget
        self.currencyCode = currencyCode
    }

    /// Hand-edited values that do not parse are dropped field by field instead of failing the whole plan.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.planMonthlyPrice = try? container.decodeIfPresent(Double.self, forKey: .planMonthlyPrice)
        self.monthlyBudget = try? container.decodeIfPresent(Double.self, forKey: .monthlyBudget)
        self.currencyCode = try? container.decodeIfPresent(String.self, forKey: .currencyCode)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.planMonthlyPrice, forKey: .planMonthlyPrice)
        try container.encodeIfPresent(self.monthlyBudget, forKey: .monthlyBudget)
        try container.encodeIfPresent(self.currencyCode, forKey: .currencyCode)
    }

    public var validPlanMonthlyPrice: Double? {
        Self.validAmount(self.planMonthlyPrice)
    }

    public var validMonthlyBudget: Double? {
        Self.validAmount(self.monthlyBudget)
    }

    /// No usable amount, so nothing reads this plan.
    public var isEmpty: Bool {
        self.validPlanMonthlyPrice == nil && self.validMonthlyBudget == nil
    }

    /// The stored currency when it is a valid code, otherwise `fallback` (the provider's cost currency).
    public func resolvedCurrencyCode(fallback: String?) -> String {
        Self.normalizedCurrencyCode(self.currencyCode)
            ?? Self.normalizedCurrencyCode(fallback)
            ?? Self.fallbackCurrencyCode
    }

    /// A positive, finite amount no larger than `maximumAmount`.
    public static func validAmount(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= self.maximumAmount else { return nil }
        return value
    }

    /// Three ASCII letters, uppercased; anything else is not a currency code.
    public static func normalizedCurrencyCode(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              trimmed.count == 3,
              trimmed.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 })
        else { return nil }
        return trimmed
    }
}

// MARK: - Amount text

extension ProviderSpendPlan {
    /// Parses an amount typed into a settings field: `200`, `19.99`, `19,99`, `$1,200.50` or `1.200,50`.
    ///
    /// Currency symbols and spaces are ignored. With both separators present, the last one is the decimal
    /// separator. A lone separator is decimal when it matches `decimalSeparator` or is not followed by
    /// exactly three digits; otherwise it groups thousands. Returns `nil` for text that is not a number.
    public static func parseAmount(_ text: String, decimalSeparator: String = ".") -> Double? {
        let kept = text.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == "," || $0 == "-") }
        guard !kept.isEmpty, kept.contains(where: \.isNumber) else { return nil }
        let separators = kept.filter { $0 == "." || $0 == "," }
        let normalized: String
        if let last = separators.last, separators.contains(where: { $0 != last }) {
            normalized = Self.joined(kept, decimal: last)
        } else if let only = separators.first {
            let occurrences = separators.count
            let fraction = kept.split(separator: only, omittingEmptySubsequences: false).last ?? ""
            let isDecimal = occurrences == 1
                && (String(only) == decimalSeparator || fraction.count != 3)
            normalized = isDecimal ? Self.joined(kept, decimal: only) : kept.replacingOccurrences(
                of: String(only),
                with: "")
        } else {
            normalized = kept
        }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// Drops every separator except the last `decimal` one, which becomes a period.
    private static func joined(_ text: String, decimal: Character) -> String {
        guard let index = text.lastIndex(of: decimal) else { return text }
        let integer = String(text[..<index]).filter { $0 != "." && $0 != "," }
        let fraction = String(text[text.index(after: index)...]).filter { $0 != "." && $0 != "," }
        return integer + "." + fraction
    }
}

// MARK: - Provider config

extension ProviderConfig {
    /// The user's plan price and budget for this provider; `nil` when neither is set.
    public var spendPlan: ProviderSpendPlan? {
        get {
            let plan: ProviderSpendPlan? = self.extensionValue(forKey: "spendPlan")
            return plan?.isEmpty == false ? plan : nil
        }
        set {
            let plan = newValue?.isEmpty == false ? newValue : nil
            self.setExtensionValue(plan, forKey: "spendPlan")
        }
    }
}
