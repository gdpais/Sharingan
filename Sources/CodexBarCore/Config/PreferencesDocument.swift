import Foundation

/// Explicit transfer format. The allowlist is deliberately independent of defaults search domains.
public struct PreferencesDocument: Codable, Sendable {
    public enum Error: LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            switch self {
            case let .invalid(message): message
            }
        }
    }

    public static let pendingImportKey = "portablePreferencesPendingImport"
    /// Distributed notification the CLI posts after queueing an import into the app's defaults domain.
    public static let importNotification = "\(AppDefaultsDomain.release).preferencesImport"
    public static let defaultsDomain = AppDefaultsDomain.release
    private var version = 1
    private var preferences: [String: ProviderConfigExtensionValue] = [:]
    /// Structured sections sit beside `preferences`, never inside it: older readers reject unknown keys in
    /// `preferences` but skip unknown top-level keys, so a document with sections still imports there, without
    /// them. A missing section leaves that part of the receiving Mac alone. A new section follows the same
    /// pattern: an optional top-level value with its own format, which builds that do not know it skip.
    public var menuBarLayout: SyncedMenuBarLayout?
    public var menuCardLayouts: SyncedMenuCardLayouts?
    /// The `SyncedPreferences` properties that travel as the sections above.
    private static let sectionKeys: Set<String> = ["menuBarLayout", "menuCardLayouts"]

    private static let boolKeys = Set([
        "statusChecksEnabled", "sessionQuotaNotificationsEnabled", "quotaWarningNotificationsEnabled",
        "predictivePaceWarningNotificationsEnabled", "quotaWarningSessionEnabled", "quotaWarningWeeklyEnabled",
        "quotaWarningSoundEnabled", "quotaWarningOnScreenAlertEnabled", "quotaWarningMarkersVisible", "paceVisible",
        "usageBarsShowUsed", "resetTimesShowAbsolute", "costUsageEnabled", "costComparisonPeriodsEnabled",
        "hidePersonalInfo", "randomBlinkEnabled", "confettiOnSessionLimitResetsEnabled",
        "confettiOnWeeklyLimitResetsEnabled", "limitResetNotificationsEnabled", "menuBarShowsHighestUsage",
        "showOptionalCreditsAndExtraUsage", "providerChangelogLinksEnabled", "providersSortedAlphabetically",
        "refreshAllProvidersOnMenuOpen", "mergeIcons", "mergeIconsStacked", "switcherShowsIcons",
        "menuBarColorByProvider",
    ])
    private static let stringChoices: [String: [String]] = [
        "refreshFrequency": [
            "manual",
            "oneMinute",
            "twoMinutes",
            "fiveMinutes",
            "fifteenMinutes",
            "thirtyMinutes",
            "adaptive",
            "adaptiveAgentAware",
        ],
        "costSummaryDisplayStyle": ["inlineSummary", "costSubmenu", "both"],
        "workdayTickAppearance": ["hidden", "subtle", "highContrast"],
        "mergedOverviewLayout": ["detailed", "compact"],
        "unifiedIconSource": ["currentSelection", "highestUsage", "frontmostApp"],
    ]
    private static let thresholdKeys = Set([
        "quotaWarningThresholds", "quotaWarningSessionThresholds", "quotaWarningWeeklyThresholds",
    ])
    private static var keys: Set<String> {
        self.boolKeys.union(self.stringChoices.keys).union(self.thresholdKeys).union([
            "weeklyProgressWorkDays", "preferredCurrencyCode", "mergedOverviewSelectedProviders",
            "switcherShortcuts",
        ])
    }

    public init() {}

    public var isEmpty: Bool {
        self.preferences.isEmpty && self.menuBarLayout == nil && self.menuCardLayouts == nil
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
        try self.validate()
    }

    public func encoded() throws -> Data {
        try self.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func value<T: Decodable>(_ key: String, as _: T.Type = T.self) throws -> T? {
        guard let value = self.preferences[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    public mutating func set(_ key: String, _ value: some Encodable) throws {
        self.preferences[key] = try JSONDecoder().decode(
            ProviderConfigExtensionValue.self, from: JSONEncoder().encode(value))
    }

    public func merging(_ incoming: Self) -> Self {
        var result = self
        result.preferences.merge(incoming.importingPreferences) { _, new in new }
        result.menuBarLayout = incoming.menuBarLayout.map { self.menuBarLayout?.merging($0) ?? $0 }
            ?? self.menuBarLayout
        result.menuCardLayouts = incoming.menuCardLayouts ?? self.menuCardLayouts
        return result
    }

    private var importingPreferences: [String: ProviderConfigExtensionValue] {
        var values = self.preferences
        // Older exports must still replace a newer icon-source choice, including queued CLI imports.
        if values["unifiedIconSource"] == nil, case let .bool(highest)? = values["menuBarShowsHighestUsage"] {
            values["unifiedIconSource"] = .string(highest ? "highestUsage" : "currentSelection")
        }
        return values
    }

    public init(defaults: UserDefaults) throws {
        for key in Self.keys {
            let defaultsKey = key == "costUsageEnabled" ? "tokenCostUsageEnabled" : key
            guard let value = defaults.object(forKey: defaultsKey) else { continue }
            let data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
            self.preferences[key] = try JSONDecoder().decode(ProviderConfigExtensionValue.self, from: data)
        }
        self.menuBarLayout = SyncedMenuBarLayout(defaults: defaults)
        self.menuCardLayouts = SyncedMenuCardLayouts(defaults: defaults)
        if let pending = defaults.data(forKey: Self.pendingImportKey) {
            self = try self.merging(Self(data: pending))
        }
        try self.validate()
    }

    public func applying(to current: SyncedPreferences) throws -> SyncedPreferences {
        var values = try JSONDecoder().decode(
            [String: ProviderConfigExtensionValue].self, from: JSONEncoder().encode(current))
        // Optional fields omitted by the encoder still belong to the sync projection.
        let keys = Set(values.keys).union([
            "weeklyProgressWorkDays", "paceVisible", "workdayTickAppearance", "unifiedIconSource",
        ])
        values.merge(self.importingPreferences.filter { keys.contains($0.key) }) { _, new in new }
        var result = try JSONDecoder().decode(SyncedPreferences.self, from: JSONEncoder().encode(values))
        // Sections apply only when the document has them; nil leaves the current layouts alone.
        result.menuBarLayout = self.menuBarLayout
        result.menuCardLayouts = self.menuCardLayouts
        return result
    }

    public mutating func include(_ synced: SyncedPreferences) throws {
        var values = try JSONDecoder().decode(
            [String: ProviderConfigExtensionValue].self, from: JSONEncoder().encode(synced))
        for key in Self.sectionKeys {
            values.removeValue(forKey: key)
        }
        self.preferences.merge(values) { _, new in new }
        if synced.weeklyProgressWorkDays == nil { self.preferences["weeklyProgressWorkDays"] = .null }
        self.menuBarLayout = synced.menuBarLayout ?? self.menuBarLayout
        self.menuCardLayouts = synced.menuCardLayouts ?? self.menuCardLayouts
    }

    public func queueImport(in defaults: UserDefaults) throws {
        let previous = try defaults.data(forKey: Self.pendingImportKey).map(Self.init(data:)) ?? Self()
        try defaults.set(previous.merging(self).encoded(), forKey: Self.pendingImportKey)
        defaults.synchronize()
    }

    public func validate() throws {
        guard self.version == 1 else { throw Error.invalid("Unsupported preferences version") }
        for (key, value) in self.preferences {
            let valid: Bool
            switch value {
            case .bool: valid = Self.boolKeys.contains(key)
            case let .string(raw):
                valid = Self.stringChoices[key]?.contains(raw)
                    ??
                    (key == "preferredCurrencyCode" &&
                        (raw == "auto" || (raw.count == 3 && raw.utf8.allSatisfy { (65...90).contains($0) })))
            case let .integer(number): valid = key == "weeklyProgressWorkDays" && (1...7).contains(number)
            case .null: valid = key == "weeklyProgressWorkDays"
            case let .array(values):
                if Self.thresholdKeys.contains(key) {
                    valid = values
                        .allSatisfy {
                            if case let .integer(n) = $0 { return QuotaWarningThresholds.allowedRange.contains(Int(n))
                            }; return false
                        }
                } else {
                    valid = key == "mergedOverviewSelectedProviders" && values.count <= 6 && values.allSatisfy {
                        if case let .string(raw) = $0 { return ProviderInstanceID(rawValue: raw) != nil }; return false
                    }
                }
            case .object:
                valid = key == "switcherShortcuts"
                if valid { _ = try ProviderSwitcherShortcuts.validated(self.value(key) ?? [:]) }
            default: valid = false
            }
            guard valid else { throw Error.invalid("Invalid or non-portable preference: \(key)") }
        }
        try self.menuBarLayout?.validate()
        try self.menuCardLayouts?.validate()
    }
}
