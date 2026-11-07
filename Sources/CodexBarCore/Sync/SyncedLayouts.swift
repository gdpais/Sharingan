import Foundation

// MARK: - Menu bar layout

/// The menu bar layout as portable preferences and iCloud sync carry it: the layout for every provider, the
/// conditional rules it places, per-provider overrides, and the layout's display options.
///
/// The layout model lives in the app, so its parts stay JSON here. The app decodes them with its own types and
/// checks them like the layout editor does before it applies anything. Every part is optional: a missing part
/// leaves that part of the receiving Mac's layout as it is. The vertical nudge stays on each Mac, because it is
/// tuned to that Mac's displays.
public struct SyncedMenuBarLayout: Codable, Sendable, Equatable {
    /// The parts that hold the app's layout JSON.
    public enum Part: String, CaseIterable, Sendable {
        /// The layout for every provider. Absent while the app still derives it from the display mode.
        case layout
        /// The conditional rules the layouts place by ID.
        case conditionals
        /// Per-provider layouts keyed by provider instance ID.
        case overrides
    }

    /// Raised only for a change older builds would misread. A build skips a format it does not know.
    public static let currentFormat = 1
    public static let sizeChoices = ["small", "regular", "large"]
    public static let gapChoices = ["tight", "regular"]
    /// Where the app stores each part, newest generation first (`MenuBarLayoutUserDefaultsKey`).
    public static let layoutDefaultsKeys = [
        "menuBarLayoutV6", "menuBarLayoutV5", "menuBarLayoutV4", "menuBarLayoutV3", "menuBarLayoutV2",
        "menuBarLayout",
    ]
    public static let conditionalsDefaultsKeys = [
        "menuBarLayoutConditionalsV6", "menuBarLayoutConditionalsV5", "menuBarLayoutConditionalsV4",
        "menuBarLayoutConditionalsV3", "menuBarLayoutConditionalsV2", "menuBarLayoutConditionals",
    ]
    public static let overridesDefaultsKeys = [
        "menuBarLayoutOverridesV6", "menuBarLayoutOverridesV5", "menuBarLayoutOverridesV4",
        "menuBarLayoutOverridesV3", "menuBarLayoutOverridesV2", "menuBarLayoutOverrides",
    ]

    public let format: Int
    private var layout: ProviderConfigExtensionValue?
    private var conditionals: ProviderConfigExtensionValue?
    private var overrides: ProviderConfigExtensionValue?
    public var size: String?
    public var gap: String?
    public var monospacedDigits: Bool?
    public var showWindowLabels: Bool?

    public init(format: Int = SyncedMenuBarLayout.currentFormat) {
        self.format = format
    }

    public var isSupported: Bool {
        Self.supports(self.format)
    }

    public func has(_ part: Part) -> Bool {
        self.json(for: part) != nil
    }

    public mutating func set(_ part: Part, _ value: some Encodable) throws {
        let json = try JSONDecoder().decode(ProviderConfigExtensionValue.self, from: JSONEncoder().encode(value))
        switch part {
        case .layout: self.layout = json
        case .conditionals: self.conditionals = json
        case .overrides: self.overrides = json
        }
    }

    public func value<T: Decodable>(_ part: Part, as _: T.Type = T.self) throws -> T? {
        guard let json = self.json(for: part) else { return nil }
        return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(json))
    }

    /// `newer`'s parts over these, part by part, so a queued import carrying only some parts keeps the others.
    public func merging(_ newer: SyncedMenuBarLayout) -> SyncedMenuBarLayout {
        guard newer.isSupported else { return self.isSupported ? self : newer }
        guard self.isSupported else { return newer }
        var result = self
        result.layout = newer.layout ?? self.layout
        result.conditionals = newer.conditionals ?? self.conditionals
        result.overrides = newer.overrides ?? self.overrides
        result.size = newer.size ?? self.size
        result.gap = newer.gap ?? self.gap
        result.monospacedDigits = newer.monospacedDigits ?? self.monospacedDigits
        result.showWindowLabels = newer.showWindowLabels ?? self.showWindowLabels
        return result
    }

    /// Shape checks that need no app types. The app checks the layouts themselves before applying them.
    public func validate() throws {
        guard self.isSupported else { return }
        let valid = (self.layout.map(Self.isObject) ?? true)
            && (self.conditionals.map(Self.isArray) ?? true)
            && (self.overrides.map(Self.isOverrides) ?? true)
            && (self.size.map { Self.sizeChoices.contains($0) } ?? true)
            && (self.gap.map { Self.gapChoices.contains($0) } ?? true)
        guard valid else {
            throw PreferencesDocument.Error.invalid("Invalid or non-portable preference: menuBarLayout")
        }
    }

    /// The layout the app stored in `defaults`, or nil when it stored none. Only reads. Each part comes from the
    /// newest generation that holds JSON of the right shape, so a damaged value never blocks the rest of an export.
    public init?(defaults: UserDefaults) {
        self.init()
        self.layout = Self.newestStored(in: defaults, keys: Self.layoutDefaultsKeys, where: Self.isObject)
        self.conditionals = Self.newestStored(in: defaults, keys: Self.conditionalsDefaultsKeys, where: Self.isArray)
        self.overrides = Self.newestStored(in: defaults, keys: Self.overridesDefaultsKeys, where: Self.isOverrides)
        self.size = defaults.string(forKey: "menuBarLayoutSize").flatMap { Self.sizeChoices.contains($0) ? $0 : nil }
        self.gap = defaults.string(forKey: "menuBarLayoutGap").flatMap { Self.gapChoices.contains($0) ? $0 : nil }
        self.monospacedDigits = defaults.object(forKey: "menuBarLayoutMonospacedDigits") as? Bool
        self.showWindowLabels = defaults.object(forKey: "menuBarLayoutShowWindowLabels") as? Bool
        guard self != SyncedMenuBarLayout() else { return nil }
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case format, layout, conditionals, overrides, size, gap, monospacedDigits, showWindowLabels
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Int.self, forKey: .format)
        self.format = format
        // A newer format may change what the parts mean, so they are skipped rather than misread.
        guard Self.supports(format) else { return }
        self.layout = try container.decodeIfPresent(ProviderConfigExtensionValue.self, forKey: .layout)
        self.conditionals = try container.decodeIfPresent(ProviderConfigExtensionValue.self, forKey: .conditionals)
        self.overrides = try container.decodeIfPresent(ProviderConfigExtensionValue.self, forKey: .overrides)
        self.size = try container.decodeIfPresent(String.self, forKey: .size)
        self.gap = try container.decodeIfPresent(String.self, forKey: .gap)
        self.monospacedDigits = try container.decodeIfPresent(Bool.self, forKey: .monospacedDigits)
        self.showWindowLabels = try container.decodeIfPresent(Bool.self, forKey: .showWindowLabels)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.format, forKey: .format)
        try container.encodeIfPresent(self.layout, forKey: .layout)
        try container.encodeIfPresent(self.conditionals, forKey: .conditionals)
        try container.encodeIfPresent(self.overrides, forKey: .overrides)
        try container.encodeIfPresent(self.size, forKey: .size)
        try container.encodeIfPresent(self.gap, forKey: .gap)
        try container.encodeIfPresent(self.monospacedDigits, forKey: .monospacedDigits)
        try container.encodeIfPresent(self.showWindowLabels, forKey: .showWindowLabels)
    }

    // MARK: Helpers

    private static func supports(_ format: Int) -> Bool {
        (1...self.currentFormat).contains(format)
    }

    private func json(for part: Part) -> ProviderConfigExtensionValue? {
        switch part {
        case .layout: self.layout
        case .conditionals: self.conditionals
        case .overrides: self.overrides
        }
    }

    private static func newestStored(
        in defaults: UserDefaults,
        keys: [String],
        where isValid: (ProviderConfigExtensionValue) -> Bool) -> ProviderConfigExtensionValue?
    {
        for key in keys {
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(ProviderConfigExtensionValue.self, from: data),
                  isValid(value)
            else { continue }
            return value
        }
        return nil
    }

    private static func isObject(_ value: ProviderConfigExtensionValue) -> Bool {
        if case .object = value { return true }
        return false
    }

    private static func isArray(_ value: ProviderConfigExtensionValue) -> Bool {
        if case .array = value { return true }
        return false
    }

    /// An object of layout objects keyed by provider instance ID.
    private static func isOverrides(_ value: ProviderConfigExtensionValue) -> Bool {
        guard case let .object(layouts) = value else { return false }
        return layouts.allSatisfy { key, layout in
            ProviderInstanceID(rawValue: key) != nil && self.isObject(layout)
        }
    }
}

// MARK: - Menu card layouts

/// Per-provider menu card layouts (the card builder's section order and visibility, chart and hidden menu links) as
/// portable preferences and iCloud sync carry them.
///
/// The set is complete: a provider missing from `layouts` goes back to the default card on the receiving Mac.
public struct SyncedMenuCardLayouts: Codable, Sendable, Equatable {
    /// Raised only for a change older builds would misread. A build skips a format it does not know.
    public static let currentFormat = 1
    /// Where the app stores the layouts: a dictionary of layout JSON keyed by provider ID.
    public static let defaultsKey = "menuCardLayouts"

    public let format: Int
    /// Customized layouts keyed by provider ID. Default layouts are left out.
    public private(set) var layouts: [String: MenuCardLayout]

    public init(layouts: [String: MenuCardLayout], format: Int = SyncedMenuCardLayouts.currentFormat) {
        self.format = format
        self.layouts = layouts.filter { !$0.value.isDefault }
    }

    public var isSupported: Bool {
        Self.supports(self.format)
    }

    public func validate() throws {
        guard self.isSupported else { return }
        guard self.layouts.keys.allSatisfy({ ProviderInstanceID(rawValue: $0) != nil }) else {
            throw PreferencesDocument.Error.invalid("Invalid or non-portable preference: menuCardLayouts")
        }
    }

    /// The layouts the app stored in `defaults`, or nil when it stored none. Only reads; unreadable entries are
    /// left out, as the app shows the default card for them.
    public init?(defaults: UserDefaults) {
        guard let stored = defaults.dictionary(forKey: Self.defaultsKey) else { return nil }
        var layouts: [String: MenuCardLayout] = [:]
        for (key, value) in stored {
            guard ProviderInstanceID(rawValue: key) != nil,
                  let json = value as? String,
                  let layout = MenuCardLayout.decoded(fromJSON: json)
            else { continue }
            layouts[key] = layout
        }
        self.init(layouts: layouts)
    }

    private enum CodingKeys: String, CodingKey {
        case format, layouts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Int.self, forKey: .format)
        self.format = format
        if Self.supports(format) {
            self.layouts = try container.decodeIfPresent([String: MenuCardLayout].self, forKey: .layouts) ?? [:]
        } else {
            // A newer format may store layouts differently, so they are skipped rather than misread.
            self.layouts = [:]
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.format, forKey: .format)
        try container.encode(self.layouts, forKey: .layouts)
    }

    private static func supports(_ format: Int) -> Bool {
        (1...self.currentFormat).contains(format)
    }
}
