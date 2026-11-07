import CodexBarCore
import Foundation

// MARK: - Menu bar layout check

/// A synced or imported menu bar layout in the app's own types, checked the way the layout editor checks it.
struct MenuBarLayoutImport: Equatable {
    var layout: MenuBarLayout?
    var conditionals: [MenuBarLayoutConditional]?
    var overrides: [String: MenuBarLayout]?
    var size: MenuBarLayoutSize?
    var gap: MenuBarLayoutGap?
    var monospacedDigits: Bool?
    var showWindowLabels: Bool?

    /// The section as the app would apply it, or nil for a format this build does not know (skipped, never
    /// applied). Throws, before anything is applied, for a layout the editor could not have produced.
    static func validated(
        _ synced: SyncedMenuBarLayout,
        currentConditionals: [MenuBarLayoutConditional]) throws -> MenuBarLayoutImport?
    {
        guard synced.isSupported else { return nil }
        try synced.validate()
        var result = MenuBarLayoutImport()
        do {
            // The same decoders the app loads its own layouts with, so they normalize the same way: at most two
            // lines, at most four clauses per rule, thresholds clamped to each metric's range.
            result.layout = try synced.value(.layout, as: MenuBarLayout.self)
            result.conditionals = try synced.value(.conditionals, as: [MenuBarLayoutConditional].self)
                .map(Self.editorNamed)
            result.overrides = try synced.value(.overrides, as: [String: MenuBarLayout].self)
        } catch {
            throw Self.invalid()
        }
        result.size = synced.size.flatMap(MenuBarLayoutSize.init(rawValue:))
        result.gap = synced.gap.flatMap(MenuBarLayoutGap.init(rawValue:))
        result.monospacedDigits = synced.monospacedDigits
        result.showWindowLabels = synced.showWindowLabels
        if let conditionals = result.conditionals {
            try Self.validateLibrary(conditionals)
        }
        let conditionalIDs = Set((result.conditionals ?? currentConditionals).map(\.id))
        var layouts: [MenuBarLayout] = result.overrides.map { Array($0.values) } ?? []
        if let layout = result.layout {
            layouts.append(layout)
        }
        for layout in layouts {
            try Self.validateLayout(layout, conditionalIDs: conditionalIDs)
        }
        return result
    }

    /// The editor's rules for the rule library: every rule has its own ID, and both branches are tokens the
    /// rule editor's branch menu offers.
    static func validateLibrary(_ conditionals: [MenuBarLayoutConditional]) throws {
        let branches = Set(MenuBarLayoutPaletteTokens.conditionalBranch)
        var ids: Set<UUID> = []
        for conditional in conditionals {
            guard ids.insert(conditional.id).inserted,
                  branches.contains(conditional.thenToken),
                  branches.contains(conditional.elseToken)
            else { throw Self.invalid() }
        }
    }

    /// The editor never leaves a layout without a token other than spacing, and removing a rule removes its chips,
    /// so a layout shows something and places only rules from the library.
    static func validateLayout(_ layout: MenuBarLayout, conditionalIDs: Set<UUID>) throws {
        let tokens = Array(layout.lines.joined())
        guard tokens.contains(where: { $0 != .space }) else { throw Self.invalid() }
        for token in tokens {
            if case let .conditional(id) = token, !conditionalIDs.contains(id) {
                throw Self.invalid()
            }
        }
    }

    /// Gives each rule a name the editor accepts, non-empty and unique ignoring case and surrounding spaces, the way
    /// the editor names a duplicated rule. IDs stay, so placed chips still resolve. Rules saved before names
    /// existed decode with an empty name; rejecting them would drop an otherwise valid layout.
    static func editorNamed(_ conditionals: [MenuBarLayoutConditional]) -> [MenuBarLayoutConditional] {
        var taken = Set(conditionals.map { Self.nameKey($0.name) })
        var seen: Set<String> = []
        return conditionals.map { conditional in
            let key = Self.nameKey(conditional.name)
            guard key.isEmpty || !seen.insert(key).inserted else { return conditional }
            let base = conditional.displayName
            let name = taken.contains(Self.nameKey(base))
                ? MenuBarLayoutConditional.uniqueCopyName(basedOn: base, existingNames: taken)
                : base
            taken.insert(Self.nameKey(name))
            seen.insert(Self.nameKey(name))
            var named = conditional
            named.name = name
            return named
        }
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func invalid() -> PreferencesDocument.Error {
        .invalid("Invalid or non-portable preference: menuBarLayout")
    }

    /// Thrown after an interactive import applied everything except a menu bar layout this build cannot read.
    static func skipped() -> PreferencesDocument.Error {
        .invalid("Imported everything except menuBarLayout, which this version cannot read; the current menu bar "
            + "layout is unchanged")
    }
}

// MARK: - Settings

/// Menu bar and menu card layouts in portable preferences and iCloud sync. Both ride `SyncedPreferences`, so the
/// export, import, sync upload and sync apply paths all go through `syncedPreferences` and
/// `applySyncedPreferences`.
extension SettingsStore {
    /// The menu bar layout as sync and portable preferences carry it, or nil when it cannot be encoded.
    var syncedMenuBarLayout: SyncedMenuBarLayout? {
        var synced = SyncedMenuBarLayout()
        do {
            if let layout = self.defaultsState.storedMenuBarLayout {
                try synced.set(.layout, layout)
            }
            try synced.set(.conditionals, self.menuBarLayoutConditionals)
            try synced.set(
                .overrides,
                self.defaultsState.menuBarLayoutOverridesRaw.filter { ProviderInstanceID(rawValue: $0.key) != nil })
        } catch {
            return nil
        }
        synced.size = self.menuBarLayoutSize.rawValue
        synced.gap = self.menuBarLayoutGap.rawValue
        synced.monospacedDigits = self.menuBarLayoutMonospacedDigits
        synced.showWindowLabels = self.menuBarLayoutShowWindowLabels
        return synced
    }

    /// Every customized menu card layout, including ones for providers this build does not know.
    var syncedMenuCardLayouts: SyncedMenuCardLayouts {
        var layouts: [String: MenuCardLayout] = [:]
        for (key, json) in self.menuCardLayoutsRaw {
            guard ProviderInstanceID(rawValue: key) != nil, let layout = MenuCardLayout.decoded(fromJSON: json)
            else { continue }
            layouts[key] = layout
        }
        return SyncedMenuCardLayouts(layouts: layouts)
    }

    /// Checks the document's menu bar layout like the layout editor would, before any setting changes.
    func validateLayoutImport(_ document: PreferencesDocument) throws {
        guard let section = document.menuBarLayout else { return }
        _ = try MenuBarLayoutImport.validated(section, currentConditionals: self.menuBarLayoutConditionals)
    }

    /// Imports a queued document (CLI imports and the one-time CodexBar carry-over). Nobody sees an error there,
    /// so a queued menu bar layout this build rejects is dropped and logged, the current layout stays, and the
    /// rest of the document still applies.
    func importPendingPreferences(_ document: PreferencesDocument) throws {
        var document = document
        do {
            try self.validateLayoutImport(document)
        } catch {
            CodexBarLog.logger(LogCategories.settings).error("Skipped a queued menu bar layout: \(error)")
            document.menuBarLayout = nil
        }
        try self.importPreferences(document)
    }

    /// Applies the layouts in synced or imported preferences. A layout this build rejects is skipped and logged;
    /// sync has nobody to show an error to, and the current layout stays as it is.
    func applySyncedLayouts(from preferences: SyncedPreferences) {
        if let section = preferences.menuBarLayout {
            do {
                if let value = try MenuBarLayoutImport.validated(
                    section,
                    currentConditionals: self.menuBarLayoutConditionals)
                {
                    self.applyMenuBarLayoutImport(value)
                }
            } catch {
                CodexBarLog.logger(LogCategories.settings).error("Skipped a synced menu bar layout: \(error)")
            }
        }
        if let cards = preferences.menuCardLayouts {
            self.applySyncedMenuCardLayouts(cards)
        }
    }

    /// Applies a checked layout part by part. Parts that are absent, or equal to what this Mac has, are left alone,
    /// so an untouched rule library is not written out as if the user had edited it.
    func applyMenuBarLayoutImport(_ value: MenuBarLayoutImport) {
        // Rules first: the layouts below place them by ID. A rule the new library drops is removed the way the
        // editor removes one, chips included, so layouts the import leaves alone keep resolving.
        if let conditionals = value.conditionals, conditionals != self.menuBarLayoutConditionals {
            let kept = Set(conditionals.map(\.id))
            for id in self.menuBarLayoutConditionals.map(\.id) where !kept.contains(id) {
                self.removeMenuBarLayoutConditional(id: id)
            }
            self.menuBarLayoutConditionals = conditionals
        }
        if let layout = value.layout, layout != self.defaultsState.storedMenuBarLayout {
            self.menuBarLayout = layout
        }
        if let overrides = value.overrides {
            let current = self.defaultsState.menuBarLayoutOverridesRaw
            for key in current.keys.sorted() where overrides[key] == nil {
                guard let instanceID = ProviderInstanceID(rawValue: key) else { continue }
                self.removeMenuBarLayoutOverride(forInstanceID: instanceID)
            }
            for key in overrides.keys.sorted() {
                guard let layout = overrides[key], current[key] != layout,
                      let instanceID = ProviderInstanceID(rawValue: key)
                else { continue }
                self.setMenuBarLayout(layout, forInstanceID: instanceID)
            }
        }
        if let size = value.size, size != self.menuBarLayoutSize {
            self.menuBarLayoutSize = size
        }
        if let gap = value.gap, gap != self.menuBarLayoutGap {
            self.menuBarLayoutGap = gap
        }
        if let digits = value.monospacedDigits, digits != self.menuBarLayoutMonospacedDigits {
            self.menuBarLayoutMonospacedDigits = digits
        }
        if let labels = value.showWindowLabels, labels != self.menuBarLayoutShowWindowLabels {
            self.menuBarLayoutShowWindowLabels = labels
        }
    }

    /// Replaces the menu card layouts with the synced set: a provider missing from it goes back to the default card.
    /// Layouts for providers this build does not know are kept as stored JSON for builds that do.
    func applySyncedMenuCardLayouts(_ synced: SyncedMenuCardLayouts) {
        guard synced.isSupported, (try? synced.validate()) != nil else { return }
        for provider in UsageProvider.allCases {
            let layout = synced.layouts[provider.rawValue] ?? .default
            if layout != self.menuCardLayout(for: provider) {
                self.setMenuCardLayout(layout, for: provider)
            }
        }
        var raw = self.menuCardLayoutsRaw
        for key in Array(raw.keys) where UsageProvider(rawValue: key) == nil {
            raw[key] = synced.layouts[key]?.encodedJSON()
        }
        for (key, layout) in synced.layouts where UsageProvider(rawValue: key) == nil {
            raw[key] = layout.encodedJSON()
        }
        if raw != self.menuCardLayoutsRaw {
            self.menuCardLayoutsRaw = raw
        }
    }
}
