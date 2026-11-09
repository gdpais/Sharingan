import Foundation

/// The opt-in Tomoe menu bar icon style.
///
/// Persisted like the other icon styles: a defaults boolean beside `menuBarShowsBrandIconWithPercent` and
/// `menuBarHidesCritters`, read through `menuBarIconStyle`. Icon & percent still wins when both are set. A missing
/// or unreadable value means off, so existing users keep the style they had and Tomoe is never the default.
extension SettingsStore {
    static let menuBarShowsTomoeIconDefaultsKey = "menuBarShowsTomoeIcon"

    var menuBarShowsTomoeIcon: Bool {
        get { self.defaultsState.menuBarShowsTomoeIcon }
        set { self.setDefault(\.menuBarShowsTomoeIcon, newValue, key: Self.menuBarShowsTomoeIconDefaultsKey) }
    }

    static func loadMenuBarShowsTomoeIcon(userDefaults: UserDefaults) -> Bool {
        userDefaults.object(forKey: self.menuBarShowsTomoeIconDefaultsKey) as? Bool ?? false
    }
}
