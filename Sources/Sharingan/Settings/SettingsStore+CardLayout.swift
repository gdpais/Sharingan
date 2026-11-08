import Foundation
import SharinganCore

/// Per-provider menu card layouts: section order and visibility, the card's chart and hidden menu links.
///
/// Stored as a `[String: String]` defaults dictionary of layout JSON keyed by the provider's raw value, held in
/// the observable defaults state so open menus rebuild when it changes. No entry means the default layout,
/// which is today's card, so a user who never opens the card builder sees no change.
///
/// The existing in-card Live/Spend switch (`providerMenuChartModes`) keeps working: `automatic` still shows the
/// switch and opens on the tab it remembers, and picking Live or Spend here also becomes that remembered tab.
extension SettingsStore {
    static let menuCardLayoutsDefaultsKey = "menuCardLayouts"

    var menuCardLayoutsRaw: [String: String] {
        get { self.defaultsState.menuCardLayoutsRaw }
        set { self.setDefault(\.menuCardLayoutsRaw, newValue, key: Self.menuCardLayoutsDefaultsKey) }
    }

    static func loadMenuCardLayoutsRaw(userDefaults: UserDefaults) -> [String: String] {
        userDefaults.dictionary(forKey: self.menuCardLayoutsDefaultsKey) as? [String: String] ?? [:]
    }

    /// The stored layout, or the default when none is stored or the stored value is unreadable.
    func menuCardLayout(for provider: UsageProvider) -> MenuCardLayout {
        guard let json = self.menuCardLayoutsRaw[provider.rawValue] else { return .default }
        return MenuCardLayout.decoded(fromJSON: json) ?? .default
    }

    func hasCustomMenuCardLayout(for provider: UsageProvider) -> Bool {
        !self.menuCardLayout(for: provider).isDefault
    }

    func setMenuCardLayout(_ layout: MenuCardLayout, for provider: UsageProvider) {
        var layouts = self.menuCardLayoutsRaw
        if layout.isDefault {
            layouts.removeValue(forKey: provider.rawValue)
        } else if let json = layout.encodedJSON() {
            layouts[provider.rawValue] = json
        }
        if layouts != self.menuCardLayoutsRaw {
            self.menuCardLayoutsRaw = layouts
        }
        switch layout.chart {
        case .live:
            self.setMenuChartMode(.live, for: provider.instanceID)
        case .spend:
            self.setMenuChartMode(.spend, for: provider.instanceID)
        case .automatic, .burndown, .planFit, .none:
            break
        }
    }

    func updateMenuCardLayout(for provider: UsageProvider, _ mutate: (inout MenuCardLayout) -> Void) {
        var layout = self.menuCardLayout(for: provider)
        mutate(&layout)
        self.setMenuCardLayout(layout, for: provider)
    }

    /// Back to today's card. The remembered Live/Spend tab is left as it is.
    func resetMenuCardLayout(for provider: UsageProvider) {
        self.setMenuCardLayout(.default, for: provider)
    }
}
