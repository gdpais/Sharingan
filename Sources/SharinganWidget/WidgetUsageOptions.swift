import AppIntents
import Foundation
import SharinganCore
import SwiftUI
import WidgetKit

// Configuration options for the provider widgets. Every option's `automatic` case reproduces the output the
// widget had before the option existed, so a saved widget looks the same until someone edits it.

// MARK: - Usage options

/// Whether quota figures read as what is left or what is used.
enum WidgetUsageMetricChoice: String, AppEnum {
    case automatic
    case remaining
    case used

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static let caseDisplayRepresentations: [WidgetUsageMetricChoice: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Match app"),
        .remaining: DisplayRepresentation(title: "Remaining"),
        .used: DisplayRepresentation(title: "Used"),
    ]

    /// `automatic` follows the app's used/remaining preference, as every widget did before.
    func showsUsed(appSetting: Bool) -> Bool {
        switch self {
        case .automatic: appSetting
        case .remaining: false
        case .used: true
        }
    }
}

/// Which quota window the tile's headline shows.
enum WidgetUsageWindowChoice: String, AppEnum {
    case automatic
    case session
    case weekly
    case monthly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Window")

    static let caseDisplayRepresentations: [WidgetUsageWindowChoice: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Automatic"),
        .session: DisplayRepresentation(title: "Session"),
        .weekly: DisplayRepresentation(title: "Weekly"),
        .monthly: DisplayRepresentation(title: "Monthly"),
    ]

    /// `automatic` keeps the tile's own rule: the most constrained lane is the headline.
    var cadence: PlanFit.Cadence? {
        switch self {
        case .automatic: nil
        case .session: .session
        case .weekly: .weekly
        case .monthly: .monthly
        }
    }
}

/// How many days of history a chart draws.
enum WidgetHistoryRangeChoice: String, AppEnum {
    case automatic
    case last7Days
    case last30Days
    case last90Days

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Range")

    static let caseDisplayRepresentations: [WidgetHistoryRangeChoice: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Match app"),
        .last7Days: DisplayRepresentation(title: "Last 7 days"),
        .last30Days: DisplayRepresentation(title: "Last 30 days"),
        .last90Days: DisplayRepresentation(title: "Last 90 days"),
    ]

    /// Nil keeps the history the app shares, which follows its cost history setting.
    var days: Int? {
        switch self {
        case .automatic: nil
        case .last7Days: 7
        case .last30Days: 30
        case .last90Days: 90
        }
    }
}

/// The display options a configured provider widget carries.
struct WidgetUsageOptions: Equatable {
    var metric: WidgetUsageMetricChoice = .automatic
    var window: WidgetUsageWindowChoice = .automatic
    var historyRange: WidgetHistoryRangeChoice = .automatic

    func showsUsed(in snapshot: WidgetSnapshot) -> Bool {
        self.metric.showsUsed(appSetting: snapshot.usageBarsShowUsed)
    }
}

extension WidgetUsageOptions {
    init(intent: ProviderSelectionIntent) {
        self.init(metric: intent.metric, window: intent.window, historyRange: intent.range)
    }
}

extension EnvironmentValues {
    /// The configured provider widget's options; the default is an unconfigured widget.
    @Entry var widgetUsageOptions: WidgetUsageOptions = .init()
}

// MARK: - Provider options

/// The provider picker lists every provider with data in the latest snapshot, sorted by name. Saved widgets
/// keep their stored raw value even when it is not listed.
struct WidgetProviderOptions: DynamicOptionsProvider {
    func results() async throws -> [ProviderChoice] {
        Self.choices(in: WidgetSnapshotStore.load())
    }

    static func choices(in snapshot: WidgetSnapshot?) -> [ProviderChoice] {
        let enabled = Set(snapshot?.enabledProviders ?? [])
        var seen: Set<UsageProvider> = []
        let withData = (snapshot?.entries ?? []).compactMap { entry -> UsageProvider? in
            guard enabled.contains(entry.provider),
                  let provider = entry.provider.firstPartyProvider,
                  seen.insert(provider).inserted
            else { return nil }
            return provider
        }
        // Until the app has published a provider, offer the original picker set rather than an empty list.
        let providers = withData.isEmpty
            ? UsageProvider.allCases.filter { ProviderChoice(provider: $0) != nil }
            : withData
        return WidgetProviderNames.sorted(providers).compactMap { ProviderChoice(catalogProvider: $0) }
    }
}

enum WidgetProviderNames {
    static func displayName(_ provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    /// Display-name order. Ties keep the incoming order, so the result is stable.
    static func sorted(_ providers: [UsageProvider]) -> [UsageProvider] {
        providers.enumerated().sorted { lhs, rhs in
            let order = self.displayName(lhs.element).localizedStandardCompare(self.displayName(rhs.element))
            return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
        }
        .map(\.element)
    }
}

// MARK: - Headline window

enum WidgetHeadlineWindow {
    /// Limits the headline to lanes of the chosen window. With `automatic`, or when the provider reports no
    /// measured lane of that window, the lanes are returned unchanged and the usual binding-lane rule applies.
    static func apply(
        _ window: WidgetUsageWindowChoice,
        to lanes: [WidgetTileLane],
        entry: WidgetSnapshot.ProviderEntry) -> [WidgetTileLane]
    {
        guard let cadence = window.cadence else { return lanes }
        let matching = Set(lanes.filter { lane in
            lane.remainingPercent != nil && self.cadence(of: lane.id, entry: entry) == cadence
        }.map(\.id))
        guard !matching.isEmpty else { return lanes }
        // Keep the provider's binding-lane rule inside the chosen window: a model-scoped lane (Claude's
        // Opus/Sonnet weekly) must not outrank the overall lane of the same window. Other lanes of the window
        // headline only when the provider designated none of them.
        let designated = matching.intersection(lanes.filter(\.isHeadlineCandidate).map(\.id))
        let headline = designated.isEmpty ? matching : designated
        return lanes.map { lane in
            var lane = lane
            lane.isHeadlineCandidate = headline.contains(lane.id)
            return lane
        }
    }

    /// The lane's window from its recorded duration, or from the lane ID when the snapshot has no duration.
    static func cadence(of laneID: String, entry: WidgetSnapshot.ProviderEntry) -> PlanFit.Cadence? {
        let window = entry.usageRows?.first { $0.id == laneID }?.window
            ?? WidgetUsageRow.slotWindow(for: laneID, entry: entry)
        if let minutes = window?.windowMinutes, minutes > 0 {
            let cadence = PlanFit.Cadence(windowMinutes: minutes)
            return cadence == .other ? nil : cadence
        }
        let id = laneID.lowercased()
        if id == "session" || id.hasSuffix("-session") || id.hasSuffix("-5h") { return .session }
        if id == "weekly" || id.hasSuffix("-weekly") || id.hasSuffix("-7d") { return .weekly }
        if id.contains("monthly") { return .monthly }
        return nil
    }
}

// MARK: - History range

/// The daily series a history chart draws.
struct WidgetHistorySeries {
    let points: [WidgetSnapshot.DailyUsagePoint]
    /// Days the series spans for a configured range. Nil keeps the chart's point-count title.
    let dayCount: Int?
}

enum WidgetHistoryRange {
    static func series(
        for entry: WidgetSnapshot.ProviderEntry,
        range: WidgetHistoryRangeChoice,
        now: Date,
        timeZone: TimeZone = .current) -> WidgetHistorySeries
    {
        guard let days = range.days else {
            return WidgetHistorySeries(points: entry.dailyUsage, dayCount: nil)
        }
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let points = self.points(
            entry.dailyUsage,
            days: days,
            coverageDays: entry.dailyUsageHistoryDays,
            today: self.dayKey(for: now, calendar: localCalendar))
        return WidgetHistorySeries(points: points, dayCount: points.isEmpty ? nil : points.count)
    }

    /// One point per day for the last `days` days up to today, with days missing from the app's history drawn
    /// as zero. Days before the history the app covers are left out rather than shown as zero.
    static func points(
        _ source: [WidgetSnapshot.DailyUsagePoint],
        days: Int,
        coverageDays: Int?,
        today: String) -> [WidgetSnapshot.DailyUsagePoint]
    {
        var byDay: [Date: WidgetSnapshot.DailyUsagePoint] = [:]
        for point in source {
            if let date = self.date(fromDayKey: point.dayKey) {
                byDay[date] = point
            }
        }
        guard days > 0,
              let todayDate = self.date(fromDayKey: today),
              let earliest = byDay.keys.min(),
              let latest = byDay.keys.max()
        else { return [] }
        let end = max(todayDate, latest)
        let rangeStart = self.day(end, offset: -(days - 1))
        let coverageStart = coverageDays.map { self.day(end, offset: -(max(1, $0) - 1)) } ?? earliest
        let start = max(rangeStart, min(coverageStart, earliest))
        let inRange = byDay.filter { $0.key >= start }
        guard !inRange.isEmpty else { return [] }
        let isCostMode = inRange.values.allSatisfy { $0.costUSD != nil }
        var result: [WidgetSnapshot.DailyUsagePoint] = []
        var day = start
        while day <= end, result.count < days {
            result.append(inRange[day] ?? WidgetSnapshot.DailyUsagePoint(
                dayKey: self.dayKey(for: day, calendar: self.keyCalendar),
                totalTokens: 0,
                costUSD: isCostMode ? 0 : nil))
            day = self.day(day, offset: 1)
        }
        return result
    }

    /// Ninety daily bars only fit a medium tile with narrower gaps. Unconfigured charts keep their spacing.
    static func barSpacing(pointCount: Int, isRanged: Bool) -> CGFloat {
        isRanged && pointCount > 31 ? 1 : 3
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return [
            self.padded(parts.year ?? 0, width: 4),
            self.padded(parts.month ?? 0, width: 2),
            self.padded(parts.day ?? 0, width: 2),
        ].joined(separator: "-")
    }

    /// Day keys are calendar dates, so their arithmetic runs in UTC where every day is 24 hours long.
    private static let keyCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    private static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        return self.keyCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func day(_ date: Date, offset: Int) -> Date {
        date.addingTimeInterval(TimeInterval(offset) * 86400)
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

// MARK: - Switcher options

/// Which providers the Switcher pages through.
enum WidgetSwitcherIncludeChoice: String, AppEnum {
    case automatic
    case all

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Providers")

    static let caseDisplayRepresentations: [WidgetSwitcherIncludeChoice: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Default"),
        .all: DisplayRepresentation(title: "All providers"),
    ]
}

/// The order the Switcher pages in.
enum WidgetSwitcherOrderChoice: String, AppEnum {
    case automatic
    case usage
    case name

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sort by")

    static let caseDisplayRepresentations: [WidgetSwitcherOrderChoice: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Default"),
        .usage: DisplayRepresentation(title: "Usage"),
        .name: DisplayRepresentation(title: "Name"),
    ]
}

struct SwitcherSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Switcher"
    static let description = IntentDescription("Choose which providers the switcher shows and their order.")

    @Parameter(title: "Providers", default: .automatic)
    var include: WidgetSwitcherIncludeChoice

    @Parameter(title: "Sort by", default: .automatic)
    var order: WidgetSwitcherOrderChoice

    init() {
        self.include = .automatic
        self.order = .automatic
    }
}

enum WidgetSwitcherProviders {
    /// Every enabled built-in provider in the snapshot, in the app's provider order.
    static func allProviders(in snapshot: WidgetSnapshot) -> [UsageProvider] {
        let enabled = snapshot.enabledProviders
        let instanceIDs = enabled.isEmpty ? snapshot.entries.map(\.provider) : enabled
        var seen: Set<UsageProvider> = []
        return instanceIDs.compactMap { instanceID -> UsageProvider? in
            guard let provider = instanceID.firstPartyProvider,
                  ProviderChoice(catalogProvider: provider) != nil,
                  seen.insert(provider).inserted
            else { return nil }
            return provider
        }
    }

    /// Whether a Switcher writes its own first provider back as the selection every Switcher shares. Only the
    /// default membership does, and only for a stored provider no Switcher can show, so a provider picked in an
    /// All providers Switcher stays picked while a default Switcher sits beside it.
    static func repairsStoredSelection(
        _ stored: ProviderInstanceID?,
        include: WidgetSwitcherIncludeChoice,
        in snapshot: WidgetSnapshot) -> Bool
    {
        guard include == .automatic else { return false }
        guard let stored else { return true }
        return !self.allProviders(in: snapshot).contains { $0.instanceID == stored }
    }

    /// `automatic` keeps the app's order. `usage` puts the provider with the least quota left first; providers
    /// without a quota follow in their original order.
    static func ordered(
        _ providers: [UsageProvider],
        in snapshot: WidgetSnapshot,
        by order: WidgetSwitcherOrderChoice) -> [UsageProvider]
    {
        switch order {
        case .automatic:
            return providers
        case .name:
            return WidgetProviderNames.sorted(providers)
        case .usage:
            let remaining = providers.map { self.headlineRemaining(for: $0, in: snapshot) }
            return providers.indices.sorted { lhs, rhs in
                switch (remaining[lhs], remaining[rhs]) {
                case let (.some(left), .some(right)):
                    left == right ? lhs < rhs : left < right
                case (.some, .none):
                    true
                case (.none, .some):
                    false
                case (.none, .none):
                    lhs < rhs
                }
            }
            .map { providers[$0] }
        }
    }

    /// The remaining share of the lane the provider's tile would headline.
    static func headlineRemaining(for provider: UsageProvider, in snapshot: WidgetSnapshot) -> Double? {
        guard let entry = snapshot.entries.first(where: { $0.provider == provider.instanceID }) else { return nil }
        let plan = WidgetTilePlan.make(lanes: WidgetTileLane.lanes(for: entry), maxSecondaryLanes: 0)
        return plan.hero?.remainingPercent
    }
}
