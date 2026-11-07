import Foundation

/// How full each tomoe of the Tomoe menu bar icon is: session, weekly and monthly, clockwise from the top.
///
/// Each value is a fraction in `0...1` of the percent the menu bar meters fill (remaining quota by default),
/// or `nil` when the provider has no such window, which the icon draws as a faint outline.
public struct TomoeIconFills: Equatable, Sendable {
    public enum Slot: Int, CaseIterable, Sendable {
        case session
        case weekly
        case monthly
    }

    /// One quota lane offered to the icon: the percent it fills and its window length, when known.
    public struct Lane: Equatable, Sendable {
        public let percent: Double
        public let windowMinutes: Int?

        public init(percent: Double, windowMinutes: Int?) {
            self.percent = percent
            self.windowMinutes = windowMinutes
        }
    }

    /// Windows up to a day long read as the session tomoe.
    public static let sessionMaximumMinutes = 24 * 60
    /// Windows longer than a session and up to ten days read as the weekly tomoe; longer ones as monthly.
    public static let weeklyMaximumMinutes = 10 * 24 * 60

    public let session: Double?
    public let weekly: Double?
    public let monthly: Double?

    /// Fractions are clamped to `0...1`; a non-finite value counts as a missing window.
    public init(session: Double?, weekly: Double?, monthly: Double?) {
        self.session = Self.clampedFraction(session)
        self.weekly = Self.clampedFraction(weekly)
        self.monthly = Self.clampedFraction(monthly)
    }

    public init(sessionPercent: Double?, weeklyPercent: Double?, monthlyPercent: Double?) {
        self.init(
            session: Self.fraction(percent: sessionPercent),
            weekly: Self.fraction(percent: weeklyPercent),
            monthly: Self.fraction(percent: monthlyPercent))
    }

    public static let empty = Self(session: nil, weekly: nil, monthly: nil)

    public func fraction(for slot: Slot) -> Double? {
        switch slot {
        case .session: self.session
        case .weekly: self.weekly
        case .monthly: self.monthly
        }
    }

    /// A percent (`0...100`) as a fill fraction, clamped. `nil` and non-finite values stay missing.
    public static func fraction(percent: Double?) -> Double? {
        guard let percent, percent.isFinite else { return nil }
        return (percent / 100).clamped(to: 0...1)
    }

    /// The tomoe a window of this length belongs to, or `nil` when the length is unknown.
    public static func slot(windowMinutes: Int?) -> Slot? {
        guard let windowMinutes, windowMinutes > 0 else { return nil }
        if windowMinutes <= self.sessionMaximumMinutes { return .session }
        if windowMinutes <= self.weeklyMaximumMinutes { return .weekly }
        return .monthly
    }

    /// Places up to three lanes in order. A lane with a known window length goes to the tomoe for that length,
    /// one without to the tomoe at its own position. A lane whose tomoe is already taken is left out, so a
    /// second weekly window never reads as the monthly one; tomoe nobody claims stay missing.
    public static func assigning(_ lanes: [Lane?]) -> Self {
        var fractions: [Slot: Double] = [:]
        for (index, lane) in lanes.prefix(Slot.allCases.count).enumerated() {
            guard let lane, let fraction = self.fraction(percent: lane.percent) else { continue }
            guard let slot = self.slot(windowMinutes: lane.windowMinutes) ?? Slot(rawValue: index),
                  fractions[slot] == nil
            else { continue }
            fractions[slot] = fraction
        }
        return Self(session: fractions[.session], weekly: fractions[.weekly], monthly: fractions[.monthly])
    }

    /// Stable text for render signatures and cache keys, in thousandths.
    public var signature: String {
        Slot.allCases.map { slot in
            guard let fraction = self.fraction(for: slot) else { return "nil" }
            return String(Int((fraction * 1000).rounded()))
        }
        .joined(separator: ",")
    }

    private static func clampedFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value.clamped(to: 0...1)
    }
}
