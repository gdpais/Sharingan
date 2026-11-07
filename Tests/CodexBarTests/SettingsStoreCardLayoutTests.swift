import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreCardLayoutTests {
    @Test
    func `absent layouts are the default and nothing is stored`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(settings.menuCardLayout(for: .codex) == .default)
        #expect(!settings.hasCustomMenuCardLayout(for: .claude))
        #expect(defaults.object(forKey: SettingsStore.menuCardLayoutsDefaultsKey) == nil)
    }

    @Test
    func `layouts persist per provider across reloads without touching the config`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let originalConfig = try encoder.encode(settings.config)

        var codex = MenuCardLayout(chart: .burndown)
        codex.move(.cost, by: -3)
        codex.setVisible(false, for: .credits)
        codex.setMenuItem(.statusPage, visible: false)
        settings.setMenuCardLayout(codex, for: .codex)
        settings.updateMenuCardLayout(for: .claude) { $0.setVisible(false, for: .pace) }

        let reloaded = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(reloaded.menuCardLayout(for: .codex) == codex)
        #expect(!reloaded.menuCardLayout(for: .claude).isVisible(.pace))
        #expect(reloaded.menuCardLayout(for: .gemini) == .default)
        #expect(try encoder.encode(settings.config) == originalConfig)

        reloaded.resetMenuCardLayout(for: .codex)
        #expect(reloaded.menuCardLayout(for: .codex) == .default)
        #expect(reloaded.menuCardLayoutsRaw[UsageProvider.codex.rawValue] == nil)
        #expect(reloaded.menuCardLayoutsRaw[UsageProvider.claude.rawValue] != nil)
    }

    @Test
    func `unreadable stored layouts fall back to the default`() {
        let defaults = InMemoryUserDefaults()
        defaults.set([UsageProvider.codex.rawValue: "not json"], forKey: SettingsStore.menuCardLayoutsDefaultsKey)
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)
        #expect(settings.menuCardLayout(for: .codex) == .default)
    }

    @Test
    func `the remembered live or spend tab stays the automatic chart's starting tab`() {
        let defaults = InMemoryUserDefaults()
        defaults.set([UsageProvider.openai.instanceID.rawValue: "spend"], forKey: "providerMenuChartModes")
        let settings = testSettingsStore(suiteName: #function, userDefaults: defaults)

        // The legacy switch position imports as the automatic chart, which keeps the switch on that tab.
        #expect(settings.menuCardLayout(for: .openai).chart == .automatic)
        #expect(settings.menuChartMode(for: UsageProvider.openai.instanceID) == .spend)

        // Picking Live or Spend in the card builder also becomes the switch's remembered tab.
        settings.updateMenuCardLayout(for: .openai) { $0.chart = .live }
        #expect(settings.menuChartMode(for: UsageProvider.openai.instanceID) == .live)
        settings.updateMenuCardLayout(for: .openai) { $0.chart = .spend }
        #expect(settings.menuChartMode(for: UsageProvider.openai.instanceID) == .spend)

        // Other charts and a reset leave it alone.
        settings.updateMenuCardLayout(for: .openai) { $0.chart = .planFit }
        settings.resetMenuCardLayout(for: .openai)
        #expect(settings.menuChartMode(for: UsageProvider.openai.instanceID) == .spend)
        #expect(settings.menuCardLayout(for: .openai) == .default)
    }

    @Test
    func `layout changes refresh menu observation`() async {
        let settings = testSettingsStore(suiteName: #function, userDefaults: InMemoryUserDefaults())
        await confirmation { changed in
            withObservationTracking {
                _ = settings.menuObservationToken
            } onChange: {
                changed()
            }
            settings.updateMenuCardLayout(for: .codex) { $0.chart = .none }
        }
    }
}
