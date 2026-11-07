import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreTomoeIconTests {
    @Test
    func `tomoe is never the default style`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(settings.menuBarIconStyle == .critters)
        #expect(!settings.menuBarShowsTomoeIcon)
        #expect(defaults.object(forKey: SettingsStore.menuBarShowsTomoeIconDefaultsKey) == nil)
    }

    @Test
    func `the tomoe style round-trips through persistence`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        settings.menuBarIconStyle = .tomoe
        #expect(settings.menuBarIconStyle == .tomoe)
        #expect(!settings.menuBarShowsBrandIconWithPercent)

        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.menuBarIconStyle == .tomoe)

        reloaded.menuBarIconStyle = .bars
        #expect(testSettingsStore(suiteName: #function, userDefaults: defaults).menuBarIconStyle == .bars)
    }

    @Test(arguments: MenuBarIconStyle.allCases)
    func `every style round-trips through persistence`(style: MenuBarIconStyle) {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        settings.menuBarIconStyle = .tomoe
        settings.menuBarIconStyle = style
        #expect(settings.menuBarIconStyle == style)
        #expect(testSettingsStore(suiteName: #function, userDefaults: defaults).menuBarIconStyle == style)
        #expect(settings.menuBarShowsTomoeIcon == (style == .tomoe))
    }

    @Test
    func `icon and percent wins over a stored tomoe flag`() {
        let defaults = InMemoryUserDefaults()
        defaults.set(true, forKey: SettingsStore.menuBarShowsTomoeIconDefaultsKey)
        defaults.set(true, forKey: "menuBarShowsBrandIconWithPercent")
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(settings.menuBarIconStyle == .iconAndPercent)
    }

    @Test
    func `unreadable stored values fall back to the existing styles`() {
        let defaults = InMemoryUserDefaults()
        defaults.set("tomoe", forKey: SettingsStore.menuBarShowsTomoeIconDefaultsKey)
        defaults.set(true, forKey: "menuBarHidesCritters")
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(settings.menuBarIconStyle == .bars)
    }

    @Test
    func `the picker offers tomoe with a localized name`() {
        #expect(MenuBarSettingsMenuOptions.iconStyles.contains(.tomoe))
        #expect(MenuBarSettingsMenuOptions.iconStyles.first == .critters)
        #expect(!MenuBarPane.layoutEditorEnabled(for: .tomoe))
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(MenuBarIconStyle.tomoe.label == "Tomoe")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("ja") {
            #expect(MenuBarIconStyle.tomoe.label == "巴")
        }
        #expect(MenuBarIconStyle.tomoe.label != "menu_bar_style_tomoe")
        for style in MenuBarIconStyle.allCases {
            #expect(!style.label.localizedCaseInsensitiveContains("sharingan"))
        }
    }
}
