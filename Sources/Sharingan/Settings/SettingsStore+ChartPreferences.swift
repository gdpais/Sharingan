import Foundation
import SharinganCore

/// Global chart preferences (range, stacking, average line, style and palette), stored as one
/// `[String: String]` defaults dictionary outside the synced config, like the remembered chart selections.
/// Nothing is stored until the first change, so the defaults stay today's behavior.
extension SettingsStore {
    var chartPreferences: ChartPreferences {
        ChartPreferences(storage: self.userDefaults
            .dictionary(forKey: ChartPreferences.defaultsKey) as? [String: String])
    }

    func setChartPreferences(_ preferences: ChartPreferences) {
        guard preferences != self.chartPreferences else { return }
        self.userDefaults.set(preferences.storage, forKey: ChartPreferences.defaultsKey)
        ChartPaletteSetting.apply(preferences.paletteMode)
    }
}
