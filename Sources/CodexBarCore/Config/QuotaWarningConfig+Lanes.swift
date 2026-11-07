import Foundation

/// Ids for quota lanes beyond the session and weekly windows.
///
/// A lane id names one of a provider's further usage windows: `tertiary` for its third window (labelled
/// by the provider, for example "Monthly" or a model family), or the id of a provider-reported extra
/// window. A lane without an override keeps sharing the weekly warning settings, as it always has.
public enum QuotaWarningLaneID {
    public static let tertiary = "tertiary"
}

extension QuotaWarningConfig {
    /// Lane ids that carry their own override, sorted for stable iteration.
    public var laneOverrideIDs: [String] {
        (self.windows ?? [:])
            .filter(\.value.hasOverride)
            .map(\.key)
            .sorted()
    }

    public func laneConfig(_ laneID: String) -> QuotaWarningWindowConfig? {
        self.windows?[laneID]
    }

    public func hasLaneOverride(_ laneID: String) -> Bool {
        self.laneConfig(laneID)?.hasOverride ?? false
    }

    /// The lane's own thresholds when it overrides them, otherwise `fallback`.
    public func thresholds(forLane laneID: String, fallback: [Int]) -> [Int] {
        QuotaWarningThresholds.sanitized(self.laneConfig(laneID)?.thresholds ?? fallback)
    }

    /// Whether warnings run for the lane: its own switch when it has an override, otherwise `fallback`.
    public func isEnabled(forLane laneID: String, fallback: Bool) -> Bool {
        guard let config = self.laneConfig(laneID), config.hasOverride else { return fallback }
        return config.isEnabled(global: fallback)
    }

    /// Replaces the lane's override. A config without an override removes the lane entry, and an empty
    /// lane table is dropped so untouched configs keep their shape.
    public mutating func setLaneConfig(_ config: QuotaWarningWindowConfig?, for laneID: String) {
        var windows = self.windows ?? [:]
        if let config, config.hasOverride {
            windows[laneID] = config
        } else {
            windows.removeValue(forKey: laneID)
        }
        self.windows = windows.isEmpty ? nil : windows
    }
}

// MARK: - Storage

/// Where lane overrides live in the shared config.
///
/// In memory, and in the sync payload, they are `QuotaWarningConfig.windows`. On disk they are the provider-level
/// key `quotaWarningWindows`: builds that predate lanes (upstream CodexBar reads the same config) keep unknown
/// provider keys and write them back unchanged, but they drop an unknown key nested inside `quotaWarnings`.
extension QuotaWarningConfig {
    static let laneStorageKey = "quotaWarningWindows"

    /// The part stored under `quotaWarnings`. Lane overrides go to the provider level, so a config that held
    /// nothing else stores no `quotaWarnings` at all.
    var storedWithoutLanes: QuotaWarningConfig? {
        guard self.windows != nil else { return self }
        var stored = self
        stored.windows = nil
        return stored.session == nil && stored.weekly == nil ? nil : stored
    }
}

extension ProviderConfig {
    /// `quotaWarnings` as written to disk, without its lane overrides.
    var storedQuotaWarnings: QuotaWarningConfig? {
        self.quotaWarnings?.storedWithoutLanes
    }

    /// Extension values as written to disk: the lane overrides join them under their provider-level key.
    var storedExtensionValues: [String: ProviderConfigExtensionValue] {
        guard let lanes = self.quotaWarnings?.windows, !lanes.isEmpty else { return self.extensionValues }
        var copy = self
        copy.setExtensionValue(lanes, forKey: QuotaWarningConfig.laneStorageKey)
        return copy.extensionValues
    }

    /// Moves lane overrides read from the provider-level key into `quotaWarnings.windows`.
    ///
    /// Configs written before the key existed nest them in `quotaWarnings.windows`; those are still read, and the
    /// next save writes only the provider-level key. A value that does not parse stays an opaque extension value,
    /// like any unknown key.
    ///
    /// This build never writes the nested form, so nested lanes next to the provider-level key were written later,
    /// by an older build that kept the key as an opaque value. Those edits are newer and win lane by lane.
    mutating func adoptStoredQuotaWarningLanes() {
        let key = QuotaWarningConfig.laneStorageKey
        guard self.extensionValues[key] != nil,
              let stored: [String: QuotaWarningWindowConfig] = self.extensionValue(forKey: key)
        else { return }
        self.extensionValues[key] = nil
        let nested = self.quotaWarnings?.windows ?? [:]
        let merged = stored.merging(nested) { _, newer in newer }
        let lanes = merged.isEmpty ? nil : merged
        if var warnings = self.quotaWarnings {
            warnings.windows = lanes
            self.quotaWarnings = warnings
        } else if let lanes {
            self.quotaWarnings = QuotaWarningConfig(windows: lanes)
        }
    }
}

extension QuotaWarningThresholds {
    /// How many thresholds the editor lets a user build up. A config may hold more; the editor still shows
    /// and keeps every one of them and only stops offering to add.
    public static let editorMaximumCount = 5

    /// Resolves an edited list: blank entries drop out, values clamp to the allowed range, duplicates
    /// collapse and the result sorts highest first. A list with nothing left falls back to the defaults.
    public static func resolved(entries: [Int?]) -> [Int] {
        self.sanitized(entries.compactMap(\.self))
    }

    /// The value to offer when the user adds a threshold: half of the lowest active one (a deeper
    /// warning), else the midpoint of the widest remaining gap. Nil when no whole percent is left.
    public static func suggestedAddition(to raw: [Int]) -> Int? {
        let current = self.sanitized(raw)
        let lowestActive = current.last(where: { $0 > 0 }) ?? 100
        let deeper = lowestActive / 2
        if deeper >= 1, !current.contains(deeper) {
            return deeper
        }
        let bounds = [100] + current + [0]
        var bestGap = 0
        var bestValue: Int?
        for (upper, lower) in zip(bounds, bounds.dropFirst()) {
            let gap = upper - lower
            let candidate = lower + gap / 2
            guard gap >= 2, gap > bestGap, candidate > 0,
                  self.allowedRange.contains(candidate), !current.contains(candidate)
            else { continue }
            bestGap = gap
            bestValue = candidate
        }
        return bestValue
    }
}
