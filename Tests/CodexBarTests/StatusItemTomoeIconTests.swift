import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusItemTomoeIconTests {
    @Test(arguments: [false, true])
    func `the tomoe style draws the provider's windows and switching back restores the meter`(merged: Bool) throws {
        let settings = testSettingsStore(
            suiteName: "StatusItemTomoeIconTests-\(merged)",
            userDefaults: InMemoryUserDefaults())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = merged
        settings.selectedMenuProvider = .codex
        settings.menuBarIconStyle = .bars
        enableTestProviders([.codex, .claude], settings: settings)
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: RateWindow(usedPercent: 60, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
                updatedAt: Date()),
            provider: .codex)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
        defer { controller.releaseStatusItemsForTesting() }

        func render() -> Bool {
            merged ? controller.applyIcon(phase: nil) : controller.applyIcon(for: .codex, phase: nil)
        }
        func signature() -> String? {
            merged
                ? controller.lastAppliedMergedIconRenderSignature
                : controller.lastAppliedProviderIconRenderSignatures[.codex]
        }
        _ = render()
        let button = try #require(merged ? controller.statusItem.button : controller.statusItems[.codex]?.button)
        let meter = try #require(button.image)
        #expect(signature()?.contains("tomoe=off") == true)

        settings.menuBarIconStyle = .tomoe
        #expect(!render())
        let expected = IconRenderer.makeTomoeIcon(
            fills: TomoeIconFills(session: 0.75, weekly: 0.4, monthly: nil),
            stale: false)
        #expect(button.image?.tiffRepresentation == expected.tiffRepresentation)
        #expect(signature()?.contains("tomoe=750,400,nil") == true)
        #expect(render())

        settings.menuBarIconStyle = .bars
        #expect(!render())
        #expect(button.image?.tiffRepresentation == meter.tiffRepresentation)
    }
}
