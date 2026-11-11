import Foundation
import Testing
@testable import Sharingan

struct BackgroundWorkPowerPolicyTests {
    @Test
    func `disabled mode preserves requested automatic intervals`() {
        #expect(BackgroundWorkPowerPolicy.automaticInterval(nil, lowPowerModeEnabled: false) == nil)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(300, lowPowerModeEnabled: false) == 300)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(3600, lowPowerModeEnabled: false) == 3600)
    }

    @Test
    func `enabled mode clamps automatic intervals to thirty minutes`() {
        #expect(BackgroundWorkPowerPolicy.automaticInterval(nil, lowPowerModeEnabled: true) == nil)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(60, lowPowerModeEnabled: true) == 1800)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(1800, lowPowerModeEnabled: true) == 1800)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(3600, lowPowerModeEnabled: true) == 3600)
    }

    @Test
    func `usage refresh wiring applies the shared policy`() {
        #expect(UsageStore.effectiveAutomaticRefreshInterval(
            60,
            lowPowerModeEnabled: false) == 60)
        #expect(UsageStore.effectiveAutomaticRefreshInterval(
            60,
            lowPowerModeEnabled: true) == 1800.0)
        #expect(UsageStore.effectiveAutomaticRefreshInterval(
            nil,
            lowPowerModeEnabled: true) == nil)
    }

    @Test
    func `inactive display clamps automatic intervals to thirty minutes`() {
        #expect(BackgroundWorkPowerPolicy.automaticInterval(
            nil,
            lowPowerModeEnabled: false,
            displayInactive: true) == nil)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(
            60,
            lowPowerModeEnabled: false,
            displayInactive: true) == 1800)
        #expect(BackgroundWorkPowerPolicy.automaticInterval(
            3600,
            lowPowerModeEnabled: false,
            displayInactive: true) == 3600)
        #expect(UsageStore.effectiveAutomaticRefreshInterval(
            300,
            lowPowerModeEnabled: false,
            displayInactive: true) == 1800)
        #expect(UsageStore.effectiveAutomaticRefreshInterval(
            300,
            lowPowerModeEnabled: false,
            displayInactive: false) == 300)
    }

    @Test
    func `display activation refreshes only after a missed normal tick`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(BackgroundWorkPowerPolicy.shouldRefreshOnDisplayActivation(
            lastRefreshStartedAt: now.addingTimeInterval(-600),
            normalInterval: 300,
            now: now))
        #expect(!BackgroundWorkPowerPolicy.shouldRefreshOnDisplayActivation(
            lastRefreshStartedAt: now.addingTimeInterval(-60),
            normalInterval: 300,
            now: now))
        #expect(BackgroundWorkPowerPolicy.shouldRefreshOnDisplayActivation(
            lastRefreshStartedAt: nil,
            normalInterval: 300,
            now: now))
        // Manual refresh has no normal interval, so unlocking never refreshes on its own.
        #expect(!BackgroundWorkPowerPolicy.shouldRefreshOnDisplayActivation(
            lastRefreshStartedAt: nil,
            normalInterval: nil,
            now: now))
    }

    @Test
    func `display is inactive while asleep or locked and active only when both clear`() {
        typealias Monitor = DisplayActivityMonitor
        var state = Monitor.State()
        #expect(!state.isInactive)
        state = Monitor.reduce(state, .screensDidSleep)
        #expect(state.isInactive)
        state = Monitor.reduce(state, .sessionDidLock)
        state = Monitor.reduce(state, .screensDidWake)
        #expect(state.isInactive)
        state = Monitor.reduce(state, .sessionDidUnlock)
        #expect(!state.isInactive)
    }

    @MainActor
    @Test
    func `display monitor reports transitions once`() {
        var changes: [Bool] = []
        let monitor = DisplayActivityMonitor(onChange: { changes.append($0) })
        monitor.handle(.screensDidSleep)
        monitor.handle(.sessionDidLock)
        monitor.handle(.screensDidWake)
        monitor.handle(.sessionDidUnlock)
        monitor.handle(.sessionDidUnlock)
        #expect(changes == [true, false])
    }
}
