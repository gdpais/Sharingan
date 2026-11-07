import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct LayoutPreferencesTransferTests {
    private func store(_ suffix: String, defaults: UserDefaults = InMemoryUserDefaults()) -> SettingsStore {
        testSettingsStore(suiteName: "LayoutPreferencesTransferTests-\(suffix)", userDefaults: defaults)
    }

    private static func rule(
        id: UUID = UUID(),
        name: String,
        thenToken: MenuBarLayoutToken = .percent(window: .session)) -> MenuBarLayoutConditional
    {
        MenuBarLayoutConditional(
            id: id,
            name: name,
            clauses: [MenuBarConditionalClause(
                combinator: nil,
                predicate: MenuBarConditionalPredicate(metric: .session, comparison: .greaterThan, threshold: 70))],
            thenToken: thenToken,
            elseToken: .hidden)
    }

    /// A layout touching every part: a placed rule, a provider and a plugin override, and the display options.
    private func customize(_ settings: SettingsStore) throws {
        let rule = Self.rule(name: "Busy session")
        settings.menuBarLayoutConditionals = [rule]
        settings.setMenuBarLayout(
            MenuBarLayout(lines: [[.icon, .conditional(id: rule.id)], [.percent(window: .weekly)]]),
            for: nil)
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.icon, .resetCountdown]]), for: .claude)
        let plugin = try #require(ProviderInstanceID(rawValue: "fixture-meter"))
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.percent(window: .automatic)]]), forInstanceID: plugin)
        settings.menuBarLayoutSize = .large
        settings.menuBarLayoutGap = .tight
        settings.menuBarLayoutMonospacedDigits = true
        settings.menuBarLayoutShowWindowLabels = false
    }

    private func expectSameLayout(_ target: SettingsStore, as source: SettingsStore) {
        #expect(target.hasStoredMenuBarLayout)
        #expect(target.menuBarLayout == source.menuBarLayout)
        #expect(target.menuBarLayoutConditionals == source.menuBarLayoutConditionals)
        #expect(target.defaultsState.menuBarLayoutOverridesRaw == source.defaultsState.menuBarLayoutOverridesRaw)
        #expect(target.menuBarLayoutSize == source.menuBarLayoutSize)
        #expect(target.menuBarLayoutGap == source.menuBarLayoutGap)
        #expect(target.menuBarLayoutMonospacedDigits == source.menuBarLayoutMonospacedDigits)
        #expect(target.menuBarLayoutShowWindowLabels == source.menuBarLayoutShowWindowLabels)
    }

    // MARK: Portable preferences

    @Test
    func `menu bar layout round trips through portable preferences and persists`() throws {
        let source = self.store("source")
        try self.customize(source)
        let targetDefaults = InMemoryUserDefaults()
        let target = self.store("target", defaults: targetDefaults)
        target.setMenuBarLayout(MenuBarLayout(lines: [[.icon]]), for: .codex)

        let document = try PreferencesDocument(data: source.exportPreferences().encoded())
        #expect(document.menuBarLayout?.has(.layout) == true)
        try target.importPreferences(document)

        self.expectSameLayout(target, as: source)
        // The document holds the whole set of overrides, so one only this Mac had is gone.
        #expect(target.menuBarLayoutOverrides[.codex] == nil)
        self.expectSameLayout(self.store("reloaded", defaults: targetDefaults), as: source)
        #expect(try target.exportPreferences().encoded() == source.exportPreferences().encoded())
    }

    @Test
    func `older documents without layouts leave the layouts alone`() throws {
        let settings = self.store("older-document")
        try self.customize(settings)
        settings.setMenuCardLayout(MenuCardLayout(chart: .burndown), for: .codex)
        let layoutBefore = settings.syncedMenuBarLayout
        let cardsBefore = settings.syncedMenuCardLayouts

        let document =
            try PreferencesDocument(data: Data(#"{"version":1,"preferences":{"hidePersonalInfo":true}}"#.utf8))
        #expect(document.menuBarLayout == nil)
        try settings.importPreferences(document)

        #expect(settings.hidePersonalInfo)
        #expect(settings.syncedMenuBarLayout == layoutBefore)
        #expect(settings.syncedMenuCardLayouts == cardsBefore)
    }

    @Test
    func `layouts sit beside the preferences older builds read and validate`() throws {
        let source = self.store("older-reader")
        try self.customize(source)
        let object = try #require(
            JSONSerialization.jsonObject(with: source.exportPreferences().encoded()) as? [String: Any])
        #expect(Set(object.keys) == ["version", "preferences", "menuBarLayout", "menuCardLayouts"])
        #expect(object["version"] as? Int == 1)
        let preferences = try #require(object["preferences"] as? [String: Any])
        #expect(preferences["menuBarLayout"] == nil)
        #expect(preferences["menuCardLayouts"] == nil)
        // An older build decodes `version` and `preferences`, skips unknown top-level keys, and validates only
        // `preferences`, which the unchanged allowlist accepts on its own.
        let olderView: [String: Any] = ["version": 1, "preferences": preferences]
        let older = try PreferencesDocument(data: JSONSerialization.data(withJSONObject: olderView))
        #expect(older.menuBarLayout == nil)
        #expect(try older.value("hidePersonalInfo", as: Bool.self) == source.hidePersonalInfo)
    }

    @Test
    func `sections in an unknown format are skipped rather than misread`() throws {
        let settings = self.store("future-format")
        try self.customize(settings)
        settings.setMenuCardLayout(MenuCardLayout(chart: .burndown), for: .codex)
        let layoutBefore = settings.syncedMenuBarLayout
        let cardsBefore = settings.syncedMenuCardLayouts
        let json = #"{"version":1,"preferences":{"hidePersonalInfo":true},"#
            + #""menuBarLayout":{"format":99,"layout":"tomorrow","size":7},"#
            + #""menuCardLayouts":{"format":99,"layouts":[1]}}"#

        let document = try PreferencesDocument(data: Data(json.utf8))
        #expect(document.menuBarLayout?.isSupported == false)
        #expect(document.menuCardLayouts?.isSupported == false)
        try settings.importPreferences(document)

        #expect(settings.hidePersonalInfo)
        #expect(settings.syncedMenuBarLayout == layoutBefore)
        #expect(settings.syncedMenuCardLayouts == cardsBefore)
    }

    @Test(arguments: LayoutTransferFixtures.unreadableSections)
    func `an unreadable menu bar layout is skipped and reported while the rest imports`(_ section: String) throws {
        let settings = self.store("invalid")
        try self.customize(settings)
        let before = settings.syncedMenuBarLayout
        let json = #"{"version":1,"preferences":{"hidePersonalInfo":true},"menuBarLayout":"# + section + "}"

        // A newer build can add a token without raising the format, so the layout alone is left out.
        #expect(throws: (any Error).self) {
            try settings.importPreferences(PreferencesDocument(data: Data(json.utf8)))
        }
        #expect(settings.hidePersonalInfo)
        #expect(settings.syncedMenuBarLayout == before)
    }

    @Test(arguments: LayoutTransferFixtures.malformedSections)
    func `a malformed menu bar layout section rejects the document before anything changes`(_ section: String) throws {
        let settings = self.store("malformed")
        try self.customize(settings)
        let before = settings.syncedMenuBarLayout
        let json = #"{"version":1,"preferences":{"hidePersonalInfo":true},"menuBarLayout":"# + section + "}"
        let data = Data(json.utf8)

        // Reading the file fails, so the Settings import never starts.
        #expect(throws: (any Error).self) { try PreferencesDocument(data: data) }
        #expect(!settings.hidePersonalInfo)
        #expect(settings.syncedMenuBarLayout == before)
    }

    @Test
    func `an invalid preference outside the layout still rejects the import before anything changes`() throws {
        let settings = self.store("invalid-other")
        try self.customize(settings)
        let before = settings.syncedMenuBarLayout
        let json = #"{"version":1,"preferences":{"hidePersonalInfo":true,"mergeIcons":"yes"},"#
            + #""menuBarLayout":"# + LayoutTransferFixtures.unreadableSections[0] + "}"
        // Decoded without the reading checks, so the import itself has to reject it.
        let document = try JSONDecoder().decode(PreferencesDocument.self, from: Data(json.utf8))

        #expect(throws: (any Error).self) { try settings.importPreferences(document) }
        #expect(!settings.hidePersonalInfo)
        #expect(settings.syncedMenuBarLayout == before)
    }

    @Test
    func `imported rules get editor valid names and replace the library like the editor`() throws {
        let settings = self.store("names")
        let shipped = try #require(settings.menuBarLayoutConditionals.first)
        settings.setMenuBarLayout(MenuBarLayout(lines: [[.icon, .conditional(id: shipped.id)]]), for: nil)
        let unnamed = Self.rule(name: "")
        let first = Self.rule(name: "Busy")
        let second = Self.rule(name: " busy ")
        var section = SyncedMenuBarLayout()
        try section.set(.conditionals, [unnamed, first, second])
        var document = PreferencesDocument()
        document.menuBarLayout = section

        try settings.importPreferences(document)

        let imported = settings.menuBarLayoutConditionals
        #expect(imported.map(\.id) == [unnamed.id, first.id, second.id])
        let names = imported.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        #expect(!names.contains(""))
        #expect(Set(names).count == names.count)
        #expect(imported[1].name == "Busy")
        // The layout the import left alone loses the chip of the rule it dropped, as an editor removal would.
        #expect(settings.menuBarLayout == MenuBarLayout(lines: [[.icon]]))
    }

    @Test
    func `queued imports merge layout parts`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = self.store("queued", defaults: defaults)
        let layout = MenuBarLayout(lines: [[.icon, .resetCountdown]])
        var first = PreferencesDocument()
        var layoutPart = SyncedMenuBarLayout()
        try layoutPart.set(.layout, layout)
        first.menuBarLayout = layoutPart
        var second = PreferencesDocument()
        var sizePart = SyncedMenuBarLayout()
        sizePart.size = MenuBarLayoutSize.small.rawValue
        second.menuBarLayout = sizePart

        try first.queueImport(in: defaults)
        try second.queueImport(in: defaults)
        settings.consumePendingPreferencesImport()

        #expect(settings.menuBarLayout == layout)
        #expect(settings.menuBarLayoutSize == .small)
        #expect(defaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)
    }

    @Test
    func `CLI export from the defaults domain carries the layouts`() throws {
        let defaults = InMemoryUserDefaults()
        let source = self.store("cli-source", defaults: defaults)
        try self.customize(source)
        source.setMenuCardLayout(MenuCardLayout(chart: .planFit), for: .claude)

        let document = try PreferencesDocument(data: PreferencesDocument(defaults: defaults).encoded())
        let target = self.store("cli-target")
        try target.importPreferences(document)

        self.expectSameLayout(target, as: source)
        #expect(target.menuCardLayout(for: .claude) == MenuCardLayout(chart: .planFit))
    }

    // MARK: Menu card layouts

    @Test
    func `menu card layouts round trip as a complete set and keep unknown providers`() throws {
        let source = self.store("cards-source")
        var codex = MenuCardLayout(chart: .burndown)
        codex.setVisible(false, for: .credits)
        codex.setMenuItem(.statusPage, visible: false)
        source.setMenuCardLayout(codex, for: .codex)
        let target = self.store("cards-target")
        target.setMenuCardLayout(MenuCardLayout(chart: .none), for: .claude)

        try target.importPreferences(PreferencesDocument(data: source.exportPreferences().encoded()))
        #expect(target.menuCardLayout(for: .codex) == codex)
        #expect(target.menuCardLayout(for: .claude) == .default)

        var document = PreferencesDocument()
        document.menuCardLayouts = SyncedMenuCardLayouts(layouts: ["future-provider": codex])
        try target.importPreferences(document)
        #expect(target.menuCardLayout(for: .codex) == .default)
        #expect(target.syncedMenuCardLayouts.layouts == ["future-provider": codex])
    }

    @Test
    func `menu card layouts with invalid provider keys are rejected`() {
        let json = #"{"version":1,"preferences":{},"menuCardLayouts":{"format":1,"layouts":{"Not Valid":{}}}}"#
        #expect(throws: (any Error).self) { try PreferencesDocument(data: Data(json.utf8)) }
    }

    // MARK: iCloud sync

    @Test
    func `sync payload carries the layouts and older payloads leave them alone`() throws {
        let source = self.store("sync-source")
        try self.customize(source)
        source.setMenuCardLayout(MenuCardLayout(chart: .burndown), for: .codex)
        let payload = try CanonicalSyncJSON.string(PreferencesSyncPayload(preferences: source.syncedPreferences))
        let decoded = try CanonicalSyncJSON.decode(PreferencesSyncPayload.self, from: payload)
        #expect(decoded.preferences.menuBarLayout == source.syncedMenuBarLayout)
        #expect(decoded.preferences.menuCardLayouts == source.syncedMenuCardLayouts)

        let target = self.store("sync-target")
        target.applySyncedPreferences(decoded.preferences)
        self.expectSameLayout(target, as: source)
        #expect(target.menuCardLayout(for: .codex) == MenuCardLayout(chart: .burndown))
        // The receiving Mac reports back exactly what it received, so it does not echo the layout.
        #expect(target.syncedMenuBarLayout == decoded.preferences.menuBarLayout)
        #expect(target.syncedMenuCardLayouts == decoded.preferences.menuCardLayouts)

        var object = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        var preferences = try #require(object["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "menuBarLayout")
        preferences.removeValue(forKey: "menuCardLayouts")
        object["preferences"] = preferences
        let older = try CanonicalSyncJSON.decode(
            PreferencesSyncPayload.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(older.preferences.menuBarLayout == nil)
        #expect(older.preferences.menuCardLayouts == nil)

        let untouched = self.store("sync-older")
        untouched.setMenuBarLayout(MenuBarLayout(lines: [[.icon]]), for: nil)
        untouched.setMenuCardLayout(MenuCardLayout(chart: .none), for: .claude)
        let layoutBefore = untouched.syncedMenuBarLayout
        let cardsBefore = untouched.syncedMenuCardLayouts
        untouched.applySyncedPreferences(older.preferences)
        #expect(untouched.syncedMenuBarLayout == layoutBefore)
        #expect(untouched.syncedMenuCardLayouts == cardsBefore)

        // A synced layout this build rejects is skipped; there is nobody to show an error to.
        var invalid = untouched.syncedPreferences
        var section = SyncedMenuBarLayout()
        try section.set(.layout, MenuBarLayout(lines: [[.conditional(id: UUID())]]))
        invalid.menuBarLayout = section
        untouched.applySyncedPreferences(invalid)
        #expect(untouched.syncedMenuBarLayout == layoutBefore)
    }

    // MARK: CodexBar carry-over

    @Test
    func `the one-time CodexBar import carries the menu bar layout`() throws {
        let rule = Self.rule(name: "Busy session")
        let layout = MenuBarLayout(lines: [[.icon, .conditional(id: rule.id)]])
        let override = MenuBarLayout(lines: [[.icon, .resetCountdown]])
        let encoder = JSONEncoder()
        let layoutData = try encoder.encode(layout)
        let legacy = try InMemoryUserDefaults(values: [
            "hidePersonalInfo": true,
            "menuBarLayoutV6": layoutData,
            "menuBarLayoutConditionalsV6": encoder.encode([rule]),
            "menuBarLayoutOverridesV6": encoder.encode(["claude": override]),
            "menuBarLayoutSize": "large",
            "menuBarLayoutMonospacedDigits": true,
        ])
        let appDefaults = InMemoryUserDefaults()

        #expect(LegacyPreferencesDomainImport.queueIfNeeded(into: appDefaults, legacy: legacy))
        let settings = self.store("legacy", defaults: appDefaults)
        settings.consumePendingPreferencesImport()

        #expect(settings.hidePersonalInfo)
        #expect(settings.menuBarLayout == layout)
        #expect(settings.menuBarLayoutConditionals == [rule])
        #expect(settings.menuBarLayoutOverrides[.claude] == override)
        #expect(settings.menuBarLayoutSize == .large)
        #expect(settings.menuBarLayoutMonospacedDigits)
        #expect(appDefaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)
        // The legacy domain is only read.
        #expect(legacy.data(forKey: "menuBarLayoutV6") == layoutData)
        #expect(legacy.object(forKey: "menuBarLayoutV5") == nil)
    }

    @Test
    func `a CodexBar layout this build rejects stays behind while the rest comes across`() throws {
        let encoder = JSONEncoder()
        let legacy = try InMemoryUserDefaults(values: [
            "hidePersonalInfo": true,
            "menuBarLayoutV6": encoder.encode(MenuBarLayout(lines: [[.conditional(id: UUID())]])),
            "menuBarLayoutConditionalsV6": encoder.encode([MenuBarLayoutConditional]()),
        ])
        let appDefaults = InMemoryUserDefaults()

        #expect(LegacyPreferencesDomainImport.queueIfNeeded(into: appDefaults, legacy: legacy))
        let settings = self.store("legacy-rejected", defaults: appDefaults)
        let conditionalsBefore = settings.menuBarLayoutConditionals
        settings.consumePendingPreferencesImport()

        #expect(settings.hidePersonalInfo)
        #expect(!settings.hasStoredMenuBarLayout)
        #expect(settings.menuBarLayoutConditionals == conditionalsBefore)
        #expect(appDefaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)
    }

    // MARK: Contract with the app's storage

    @Test
    func `core storage keys and choices match the app`() {
        typealias Key = MenuBarLayoutUserDefaultsKey
        #expect(SyncedMenuBarLayout.layoutDefaultsKeys == [
            Key.layoutCurrent, Key.layoutV5, Key.layoutV4, Key.layoutV3, Key.layoutReleased, Key.layout,
        ])
        #expect(SyncedMenuBarLayout.conditionalsDefaultsKeys == [
            Key.conditionalsCurrent, Key.conditionalsV5, Key.conditionalsV4, Key.conditionalsV3,
            Key.conditionalsReleased, Key.conditionals,
        ])
        #expect(SyncedMenuBarLayout.overridesDefaultsKeys == [
            Key.overridesCurrent, Key.overridesV5, Key.overridesV4, Key.overridesV3, Key.overridesReleased,
            Key.overrides,
        ])
        #expect(SyncedMenuBarLayout.sizeChoices == MenuBarLayoutSize.allCases.map(\.rawValue))
        #expect(SyncedMenuBarLayout.gapChoices == MenuBarLayoutGap.allCases.map(\.rawValue))
        #expect(SyncedMenuCardLayouts.defaultsKey == SettingsStore.menuCardLayoutsDefaultsKey)
    }

    @Test
    func `the shipped rule library passes the import checks`() throws {
        let shipped = MenuBarLayoutConditional.shippedLibrary()
        try MenuBarLayoutImport.validateLibrary(shipped)
        #expect(MenuBarLayoutImport.editorNamed(shipped) == shipped)
    }
}

/// Menu bar layout sections the layout editor could not have produced.
enum LayoutTransferFixtures {
    static let ruleID = "6F1D2C3B-4A59-4E68-8B7A-1C2D3E4F5A6B"

    static func rule(thenToken: String) -> String {
        #"{"id":"\#(self.ruleID)","name":"Loop","#
            + #""clauses":[{"predicate":{"metric":"session","comparison":"greaterThan","threshold":50}}],"#
            + #""thenToken":\#(thenToken),"elseToken":{"hidden":{}}}"#
    }

    /// Well-formed sections that this build cannot apply: skipped on import, the rest of the document applies.
    static let unreadableSections: [String] = [
        // A token this build does not know.
        #"{"format":1,"layout":{"lines":[[{"sparkles":{}}]]}}"#,
        // A placed rule missing from the library.
        #"{"format":1,"conditionals":[],"layout":{"lines":[[{"conditional":{"id":"\#(ruleID)"}}]]}}"#,
        // Nothing but spacing.
        #"{"format":1,"layout":{"lines":[[{"space":{}}]]}}"#,
        // A branch the rule editor does not offer.
        #"{"format":1,"conditionals":["# + rule(thenToken: #"{"conditional":{"id":"\#(ruleID)"}}"#) + "]}",
        // Two rules with one identity.
        #"{"format":1,"conditionals":["# + rule(thenToken: #"{"icon":{}}"#) + ","
            + rule(thenToken: #"{"icon":{}}"#) + "]}",
    ]

    /// Sections whose shape is wrong: reading the document rejects all of it.
    static let malformedSections: [String] = [
        // An override for something that cannot be a provider.
        #"{"format":1,"overrides":{"Not Valid":{"lines":[[{"icon":{}}]]}}}"#,
        // A size the editor does not offer.
        #"{"format":1,"size":"huge"}"#,
        // A layout that is not a layout object.
        #"{"format":1,"layout":[1]}"#,
    ]
}
