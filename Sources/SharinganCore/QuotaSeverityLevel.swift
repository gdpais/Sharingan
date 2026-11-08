import Foundation

/// How close a quota lane is to running out, ordered from least to most severe.
///
/// One source of truth for severity: compact account rows, menu tints and widget lanes all classify a
/// lane through `QuotaSeverityBands`, so the user's warning thresholds color every surface alike.
public enum QuotaSeverityLevel: Int, Comparable, Sendable, CaseIterable {
    case normal
    case warning
    case critical
    case exhausted

    public static func < (lhs: QuotaSeverityLevel, rhs: QuotaSeverityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Remaining-percent cut-offs that classify one quota lane.
public struct QuotaSeverityBands: Codable, Equatable, Sendable {
    /// At or below this remaining percent a lane is a warning; nil turns the band off.
    public let warningRemainingPercent: Double?
    /// At or below this remaining percent a lane is critical; nil turns the band off.
    public let criticalRemainingPercent: Double?

    public init(warningRemainingPercent: Double?, criticalRemainingPercent: Double?) {
        self.warningRemainingPercent = warningRemainingPercent
        self.criticalRemainingPercent = criticalRemainingPercent
    }

    /// The bands every surface used before warning thresholds drove severity: warning at 50% left,
    /// critical at 10% left.
    public static let standard = QuotaSeverityBands(warningRemainingPercent: 50, criticalRemainingPercent: 10)

    /// Bands for a warning-threshold list (remaining percents, as the quota warning settings store them).
    ///
    /// The untouched default list keeps `standard`, so a user who never customized thresholds sees the
    /// same colors as before. Otherwise the first (highest) active threshold starts the warning band and
    /// the second starts the critical band, matching the editor's "Warning" and "Critical" labels; any
    /// further thresholds only add notifications. An empty depleted-only list leaves just `exhausted`.
    public static func from(thresholds: [Int]) -> QuotaSeverityBands {
        let sanitized = QuotaWarningThresholds.sanitized(thresholds)
        guard sanitized != QuotaWarningThresholds.defaults else { return .standard }
        let active = sanitized.filter { $0 > 0 }
        return QuotaSeverityBands(
            warningRemainingPercent: active.first.map { Double($0) },
            criticalRemainingPercent: active.dropFirst().first.map { Double($0) })
    }

    /// Severity for a lane with `remainingPercent` left. Boundaries are inclusive, as for notifications:
    /// a lane exactly at a threshold has reached it. Non-finite input reads as normal.
    public func level(remainingPercent: Double) -> QuotaSeverityLevel {
        guard remainingPercent.isFinite else { return .normal }
        if remainingPercent <= 0 {
            return .exhausted
        }
        if let critical = self.criticalRemainingPercent, remainingPercent <= critical {
            return .critical
        }
        if let warning = self.warningRemainingPercent, remainingPercent <= warning {
            return .warning
        }
        return .normal
    }

    /// Severity for a lane that has used `usedPercent` of its quota.
    public func level(usedPercent: Double) -> QuotaSeverityLevel {
        guard usedPercent.isFinite else { return .normal }
        return self.level(remainingPercent: max(0, 100 - usedPercent))
    }

    /// Severity for a lane that has used `usedPercent`, classified by a warning-threshold list.
    public static func level(usedPercent: Double, thresholds: [Int]) -> QuotaSeverityLevel {
        self.from(thresholds: thresholds).level(usedPercent: usedPercent)
    }
}

/// Severity bands for every quota lane of one provider.
///
/// Lane ids follow the metric ids the menu and widgets use: `primary` and `session` read the session
/// bands, `secondary` and `weekly` the weekly bands, and any other lane (the provider's third window, a
/// provider-specific extra window) its own override, else the weekly bands, because those lanes have
/// always shared the weekly warning thresholds.
public struct QuotaSeverityBandSet: Codable, Equatable, Sendable {
    public var session: QuotaSeverityBands
    public var weekly: QuotaSeverityBands
    public var lanes: [String: QuotaSeverityBands]

    public init(
        session: QuotaSeverityBands = .standard,
        weekly: QuotaSeverityBands = .standard,
        lanes: [String: QuotaSeverityBands] = [:])
    {
        self.session = session
        self.weekly = weekly
        self.lanes = lanes
    }

    public static let standard = QuotaSeverityBandSet()

    public var isStandard: Bool {
        self == .standard
    }

    public func bands(forLaneID laneID: String) -> QuotaSeverityBands {
        switch laneID {
        case "primary", "session":
            self.session
        case "secondary", "weekly":
            self.weekly
        default:
            self.lanes[laneID] ?? self.weekly
        }
    }

    private enum CodingKeys: String, CodingKey {
        case session
        case weekly
        case lanes
    }

    /// Missing members decode as the standard bands so a partial payload never fails the whole snapshot.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.session = try container.decodeIfPresent(QuotaSeverityBands.self, forKey: .session) ?? .standard
        self.weekly = try container.decodeIfPresent(QuotaSeverityBands.self, forKey: .weekly) ?? .standard
        self.lanes = try container.decodeIfPresent([String: QuotaSeverityBands].self, forKey: .lanes) ?? [:]
    }
}
