import Foundation
import SharinganCore
import Testing
@testable import Sharingan

/// Warning thresholds for every window type: N thresholds per window, opt-in overrides for further lanes,
/// and the severity bands the menu and widgets derive from them.
@MainActor
struct QuotaWarningLaneTests {
    @MainActor
    final class NotifierSpy: SessionQuotaNotifying {
        private(set) var events: [QuotaWarningEvent] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider _: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            self.events.append(event)
        }
    }

    private func makeSettings(_ name: String) -> SettingsStore {
        let settings = testSettingsStore(suiteName: "QuotaWarningLaneTests-\(name)")
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        return settings
    }

    private func makeStore(settings: SettingsStore, notifier: NotifierSpy) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier)
    }

    private func snapshot(sessionUsed: Double = 0, tertiaryUsed: Double? = nil) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: sessionUsed, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 0, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil),
            tertiary: tertiaryUsed.map {
                RateWindow(usedPercent: $0, windowMinutes: 30 * 24 * 60, resetsAt: nil, resetDescription: nil)
            },
            updatedAt: Date())
    }

    // MARK: - Notifications

    @Test
    func `three or more thresholds each fire once as quota drains and refire after recovery`() {
        let settings = self.makeSettings("three-thresholds")
        settings.setQuotaWarningThresholds(.session, thresholds: [80, 50, 20])
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        for used in [10.0, 25, 55, 85, 90, 30, 60] {
            store.handleQuotaWarningTransitions(provider: .gemini, snapshot: self.snapshot(sessionUsed: used))
        }

        #expect(notifier.events.map(\.threshold) == [80, 50, 20, 50])
        #expect(notifier.events.allSatisfy { $0.window == .session && $0.windowID == nil })
    }

    @Test
    func `a jump across several thresholds posts the most severe one`() {
        let crossed = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 90,
            currentRemaining: 15,
            thresholds: [80, 60, 40, 20, 10],
            alreadyFired: [])

        #expect(crossed == 20)
        #expect(QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
            threshold: 20,
            thresholds: [80, 60, 40, 20, 10]) == [80, 60, 40, 20])
        #expect(QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 15,
            currentRemaining: 8,
            thresholds: [80, 60, 40, 20, 10],
            alreadyFired: [80, 60, 40, 20]) == 10)
    }

    @Test
    func `third windows stay silent until the user overrides them`() {
        let settings = self.makeSettings("tertiary-opt-in")
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        for used in [10.0, 80, 95] {
            store.handleQuotaWarningTransitions(provider: .gemini, snapshot: self.snapshot(tertiaryUsed: used))
        }
        #expect(notifier.events.isEmpty)
    }

    @Test
    func `overridden third windows fire on their own thresholds`() {
        let settings = self.makeSettings("tertiary-override")
        settings.setQuotaWarningLaneOverride(
            provider: .gemini,
            laneID: QuotaWarningLaneID.tertiary,
            thresholds: [60, 30, 10],
            enabled: true)
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        for used in [10.0, 45, 75, 92, 95] {
            store.handleQuotaWarningTransitions(provider: .gemini, snapshot: self.snapshot(tertiaryUsed: used))
        }

        #expect(notifier.events.map(\.threshold) == [60, 30, 10])
        #expect(notifier.events.allSatisfy { $0.window == .weekly && $0.windowID == QuotaWarningLaneID.tertiary })
        let label = ProviderDefaults.metadata[.gemini]?.opusLabel.map { L($0) }
        #expect(notifier.events.first?.windowDisplayLabel == label)
    }

    @Test
    func `an overridden lane keeps its state while the weekly window is off`() {
        let settings = self.makeSettings("tertiary-weekly-off")
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: false)
        settings.setQuotaWarningLaneOverride(
            provider: .gemini,
            laneID: QuotaWarningLaneID.tertiary,
            thresholds: [50],
            enabled: true)
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        for used in [40.0, 60, 60, 65] {
            store.handleQuotaWarningTransitions(provider: .gemini, snapshot: self.snapshot(tertiaryUsed: used))
        }

        #expect(notifier.events.map(\.threshold) == [50])
    }

    @Test
    func `a lane switched off stays silent`() {
        let settings = self.makeSettings("tertiary-off")
        settings.setQuotaWarningLaneOverride(
            provider: .gemini,
            laneID: QuotaWarningLaneID.tertiary,
            thresholds: [60],
            enabled: false)
        let notifier = NotifierSpy()
        let store = self.makeStore(settings: settings, notifier: notifier)

        for used in [10.0, 80, 95] {
            store.handleQuotaWarningTransitions(provider: .gemini, snapshot: self.snapshot(tertiaryUsed: used))
        }
        #expect(notifier.events.isEmpty)
    }

    // MARK: - Settings

    @Test
    func `the saved config keeps lane overrides at the provider level`() throws {
        let settings = self.makeSettings("lane-storage")
        settings.setQuotaWarningLaneOverride(
            provider: .gemini,
            laneID: QuotaWarningLaneID.tertiary,
            thresholds: [70, 40],
            enabled: true)

        let data = try settings.configStore.encodedData(for: settings.config)
        let saved = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let providers = try #require(saved["providers"] as? [[String: Any]])
        let gemini = try #require(providers.first { $0["id"] as? String == UsageProvider.gemini.rawValue })
        #expect(gemini["quotaWarningWindows"] != nil)
        #expect((gemini["quotaWarnings"] as? [String: Any])?["windows"] == nil)

        let reloaded = try SharinganConfig.decode(from: data)
        #expect(reloaded.providerConfig(for: UsageProvider.gemini.instanceID)?.quotaWarnings?
            .windows?[QuotaWarningLaneID.tertiary]?.thresholds == [70, 40])
    }

    @Test
    func `lane overrides persist and clear back to the weekly settings`() {
        let settings = self.makeSettings("lane-persistence")
        let lane = QuotaWarningLaneID.tertiary
        let instanceID = UsageProvider.gemini.instanceID

        #expect(settings.resolvedQuotaWarningThresholds(provider: instanceID, window: .weekly, laneID: lane)
            == settings.resolvedQuotaWarningThresholds(provider: instanceID, window: .weekly))

        settings.setQuotaWarningLaneOverride(
            provider: .gemini,
            laneID: lane,
            thresholds: [70, 40, 15, 5],
            enabled: true)
        #expect(settings.hasQuotaWarningLaneOverride(provider: .gemini, laneID: lane))
        #expect(settings.explicitQuotaWarningLaneThresholds(provider: .gemini, laneID: lane) == [70, 40, 15, 5])
        #expect(settings.quotaWarningConfig(for: instanceID).windows?[lane]?.thresholds == [70, 40, 15, 5])

        settings.setQuotaWarningLaneThresholdsIfOverridden(provider: .gemini, laneID: lane, thresholds: [70, 40])
        #expect(settings.explicitQuotaWarningLaneThresholds(provider: .gemini, laneID: lane) == [70, 40])
        #expect(settings.quotaWarningEnabled(provider: .gemini, window: .weekly, laneID: lane))

        settings.setQuotaWarningLaneOverride(provider: .gemini, laneID: lane, thresholds: nil, enabled: nil)
        #expect(!settings.hasQuotaWarningLaneOverride(provider: .gemini, laneID: lane))
        #expect(settings.providerConfig(for: .gemini)?.quotaWarnings == nil)
    }

    @Test
    func `inherited lane thresholds stay inherited until edited`() {
        let settings = self.makeSettings("lane-inherited")
        let lane = QuotaWarningLaneID.tertiary
        settings.setQuotaWarningLaneOverride(provider: .gemini, laneID: lane, thresholds: nil, enabled: true)

        settings.setQuotaWarningLaneThresholdsIfOverridden(
            provider: .gemini,
            laneID: lane,
            thresholds: settings.quotaWarningThresholds(.weekly))
        #expect(settings.explicitQuotaWarningLaneThresholds(provider: .gemini, laneID: lane) == nil)
        #expect(settings.hasQuotaWarningLaneOverride(provider: .gemini, laneID: lane))
    }

    @Test
    func `lane markers follow the lane switch and the marker preference`() {
        let settings = self.makeSettings("lane-markers")
        let lane = QuotaWarningLaneID.tertiary
        settings.quotaWarningMarkersVisible = true
        #expect(settings.quotaWarningLaneMarkerThresholds(provider: .gemini).isEmpty)

        settings.setQuotaWarningLaneOverride(provider: .gemini, laneID: lane, thresholds: [60, 30], enabled: true)
        #expect(settings.quotaWarningLaneMarkerThresholds(provider: .gemini) == [lane: [60, 30]])

        settings.setQuotaWarningLaneOverride(provider: .gemini, laneID: lane, thresholds: [60, 30], enabled: false)
        #expect(settings.quotaWarningLaneMarkerThresholds(provider: .gemini) == [lane: []])

        settings.setQuotaWarningLaneOverride(provider: .gemini, laneID: lane, thresholds: [60, 30], enabled: true)
        settings.quotaWarningMarkersVisible = false
        #expect(settings.quotaWarningLaneMarkerThresholds(provider: .gemini) == [lane: []])
    }

    @Test
    func `severity bands come from the same thresholds as warnings`() {
        let settings = self.makeSettings("severity-bands")
        #expect(settings.quotaSeverityBandSet(for: .gemini).isStandard)

        settings.setQuotaWarningThresholds(.session, thresholds: [70, 40, 10])
        settings.setQuotaWarningLaneOverride(
            provider: .gemini,
            laneID: QuotaWarningLaneID.tertiary,
            thresholds: [25, 5],
            enabled: true)
        let bands = settings.quotaSeverityBandSet(for: .gemini)

        #expect(bands.session == QuotaSeverityBands(warningRemainingPercent: 70, criticalRemainingPercent: 40))
        #expect(bands.weekly == .standard)
        #expect(bands.bands(forLaneID: QuotaWarningLaneID.tertiary)
            == QuotaSeverityBands(warningRemainingPercent: 25, criticalRemainingPercent: 5))
    }

    @Test
    func `widget entries carry bands only when thresholds are customized`() {
        let settings = self.makeSettings("widget-bands")
        let store = self.makeStore(settings: settings, notifier: NotifierSpy())
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .gemini,
            updatedAt: Date(),
            primary: nil,
            secondary: nil)

        #expect(store.widgetEntryWithSeverityBands(entry).severityBands == nil)

        settings.setQuotaWarningThresholds(.weekly, thresholds: [60, 30])
        let customized = store.widgetEntryWithSeverityBands(entry)
        #expect(customized.severityBands?.weekly
            == QuotaSeverityBands(warningRemainingPercent: 60, criticalRemainingPercent: 30))

        let account = WidgetSnapshot.AccountEntry(
            id: "acct",
            provider: UsageProvider.gemini.instanceID,
            label: "Work",
            usage: entry)
        #expect(store.widgetAccountWithSeverityBands(account).usage?.severityBands != nil)
    }

    // MARK: - Settings view

    @Test
    func `provider settings offer a lane row only for providers with a third window`() {
        let settings = self.makeSettings("lane-row")
        settings.quotaWarningMarkersVisible = true
        let gemini = ProviderQuotaWarningSettingsView(provider: .gemini, settings: settings)
        let codex = ProviderQuotaWarningSettingsView(provider: .codex, settings: settings)
        let lane = QuotaWarningLaneID.tertiary

        #expect(gemini.tertiaryLane?.id == lane)
        #expect(codex.tertiaryLane == nil)
        #expect(gemini.laneOverrideMode(for: lane) == .global)
        _ = gemini.body

        gemini.laneOverrideModeBinding(for: lane).wrappedValue = .custom
        #expect(gemini.laneOverrideMode(for: lane) == .custom)
        _ = gemini.body

        gemini.laneOverrideModeBinding(for: lane).wrappedValue = .off
        #expect(gemini.laneOverrideMode(for: lane) == .off)

        gemini.laneOverrideModeBinding(for: lane).wrappedValue = .global
        #expect(gemini.laneOverrideMode(for: lane) == .global)
        #expect(!settings.hasQuotaWarningLaneOverride(provider: .gemini, laneID: lane))
    }
}
