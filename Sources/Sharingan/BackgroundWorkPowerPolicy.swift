import Foundation

enum BackgroundWorkPowerPolicy {
    static let lowPowerMinimumInterval: TimeInterval = 30 * 60
    /// Nobody can see the menu bar while the display sleeps or the session is locked, so automatic
    /// refreshes fall back to the same floor as Low Power Mode. Stretched rather than paused so quota
    /// alerts, hooks, and widgets on other devices still move while the Mac is unattended.
    static let displayInactiveMinimumInterval: TimeInterval = 30 * 60

    static func automaticInterval(
        _ requested: TimeInterval?,
        lowPowerModeEnabled: Bool,
        displayInactive: Bool = false) -> TimeInterval?
    {
        guard let requested else { return nil }
        var interval = requested
        if lowPowerModeEnabled {
            interval = max(interval, self.lowPowerMinimumInterval)
        }
        if displayInactive {
            interval = max(interval, self.displayInactiveMinimumInterval)
        }
        return interval
    }

    /// Whether returning to an active display should refresh immediately: only when a normal tick was
    /// actually missed, so quick lock/unlock cycles neither burst refreshes nor starve the timer.
    static func shouldRefreshOnDisplayActivation(
        lastRefreshStartedAt: Date?,
        normalInterval: TimeInterval?,
        now: Date) -> Bool
    {
        guard let normalInterval else { return false }
        guard let lastRefreshStartedAt else { return true }
        return now.timeIntervalSince(lastRefreshStartedAt) >= normalInterval
    }
}
