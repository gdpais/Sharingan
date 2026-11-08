import Foundation
import SharinganCore

extension SettingsStore {
    func jetbrainsSettingsSnapshot() -> ProviderSettingsSnapshot.JetBrainsProviderSettings {
        ProviderSettingsSnapshot.JetBrainsProviderSettings(
            ideBasePath: self.jetbrainsIDEBasePath.isEmpty ? nil : self.jetbrainsIDEBasePath)
    }
}
