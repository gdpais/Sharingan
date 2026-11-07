import AppKit
import CodexBarCore

/// Inputs for the opt-in Tomoe menu bar icon style.
///
/// The first two tomoe start from the same lanes the meter styles draw (already resolved for the provider and
/// the remaining/used setting), so switching between Bars and Tomoe never changes what a lane means. The
/// provider's tertiary lane is the third candidate. Lanes with a known window length move to the session,
/// weekly or monthly tomoe that matches it (`TomoeIconFills.assigning`).
extension StatusItemController {
    var usesTomoeMenuBarIcon: Bool {
        self.settings.menuBarIconStyle == .tomoe
    }

    /// The loading pattern for meter icons. The Tomoe glyph has no bar layout to morph into, so the unbraid
    /// transition plays as a fill sweep there instead.
    var menuBarLoadingPattern: LoadingPattern {
        self.animationPattern == .unbraid && self.usesTomoeMenuBarIcon ? .cylon : self.animationPattern
    }

    /// The tomoe fills for one render, or `nil` when the Tomoe style is off.
    ///
    /// While loading, `lanes` already carry the loading pattern; the third tomoe follows it one more phase
    /// offset along, so all three animate like the meters do.
    func tomoeIconFills(
        provider: UsageProvider,
        snapshot: UsageSnapshot?,
        lanes: (primary: Double?, secondary: Double?),
        loadingPhase: Double?) -> TomoeIconFills?
    {
        guard self.usesTomoeMenuBarIcon else { return nil }
        if let loadingPhase {
            let pattern = self.menuBarLoadingPattern
            return TomoeIconFills(
                sessionPercent: lanes.primary,
                weeklyPercent: lanes.secondary,
                monthlyPercent: pattern.value(phase: loadingPhase + 2 * pattern.secondaryOffset))
        }
        let windows = snapshot.map {
            IconRemainingResolver.resolvedWindows(
                snapshot: $0,
                style: self.store.style(for: provider),
                secondaryOverrideWindowID: self.settings.copilotIconSecondaryWindowOverrideID(snapshot: $0))
        }
        return Self.resolvedTomoeIconFills(
            lanes: lanes,
            windows: (primary: windows?.primary, secondary: windows?.secondary),
            snapshot: snapshot,
            showUsed: self.settings.usageBarsShowUsed)
    }

    /// The Tomoe icon for a user plugin provider, or `nil` when the Tomoe style is off.
    func pluginTomoeIcon(
        snapshot: UsageSnapshot?,
        lanes: (primary: Double?, secondary: Double?),
        stale: Bool) -> NSImage?
    {
        guard self.usesTomoeMenuBarIcon else { return nil }
        // Without a primary or secondary window the first lane is the switcher fallback, which may already be
        // the tertiary window, so the tertiary lane is not added a second time.
        let lanesAreFallback = snapshot?.primary == nil && snapshot?.secondary == nil
        let fills = Self.resolvedTomoeIconFills(
            lanes: lanes,
            windows: (primary: snapshot?.primary, secondary: snapshot?.secondary),
            snapshot: snapshot,
            showUsed: self.settings.usageBarsShowUsed,
            includesTertiary: !lanesAreFallback)
        return IconRenderer.makeTomoeIcon(fills: fills, stale: stale)
    }

    /// The tertiary lane is the only Tomoe input the meter-icon observation signature does not already cover.
    func tomoeStoreIconObservationSignature(snapshot: UsageSnapshot?) -> String {
        guard self.usesTomoeMenuBarIcon else { return "off" }
        let lane = Self.tomoeTertiaryLane(snapshot: snapshot, showUsed: self.settings.usageBarsShowUsed)
        return "\(Self.iconSignatureValue(lane?.percent))@\(lane?.windowMinutes.map(String.init) ?? "nil")"
    }

    nonisolated static func resolvedTomoeIconFills(
        lanes: (primary: Double?, secondary: Double?),
        windows: (primary: RateWindow?, secondary: RateWindow?),
        snapshot: UsageSnapshot?,
        showUsed: Bool,
        includesTertiary: Bool = true) -> TomoeIconFills
    {
        // Some providers promote the tertiary window into the first two lanes (Perplexity's display order);
        // it then fills one tomoe, not two.
        let tertiaryIsShown = snapshot?.tertiary.map { $0 == windows.primary || $0 == windows.secondary } ?? false
        let tertiary = includesTertiary && !tertiaryIsShown
            ? self.tomoeTertiaryLane(snapshot: snapshot, showUsed: showUsed)
            : nil
        return TomoeIconFills.assigning([
            lanes.primary.map { TomoeIconFills.Lane(percent: $0, windowMinutes: windows.primary?.windowMinutes) },
            lanes.secondary.map { TomoeIconFills.Lane(percent: $0, windowMinutes: windows.secondary?.windowMinutes) },
            tertiary,
        ])
    }

    nonisolated static func tomoeTertiaryLane(snapshot: UsageSnapshot?, showUsed: Bool) -> TomoeIconFills.Lane? {
        // A synthetic placeholder stands in for a lane the provider did not report, so it stays missing.
        guard let window = snapshot?.tertiary?.measured else { return nil }
        return TomoeIconFills.Lane(
            percent: showUsed ? window.usedPercent : window.remainingPercent,
            windowMinutes: window.windowMinutes)
    }
}
