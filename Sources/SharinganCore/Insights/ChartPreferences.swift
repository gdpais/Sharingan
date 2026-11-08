import Foundation

/// How charts paint their series.
public enum ChartPaletteMode: String, CaseIterable, Equatable, Sendable {
    /// Today's colors: provider accents for single-series charts, the validated categorical order for several.
    case accents
    /// The validated categorical order everywhere, single-series charts included.
    case colorblindSafe
    /// A gray ramp, for screenshots or when color should carry no meaning.
    case monochrome
}

/// Chart choices shared by the cost history charts. Every default is the app's behavior before these
/// preferences existed, so someone who never opens them sees no change.
public struct ChartPreferences: Equatable, Sendable {
    /// How many days a chart plots.
    public enum RangeOption: String, CaseIterable, Equatable, Sendable {
        /// The History window, as before.
        case historyWindow
        case days7
        case days30
        case days90

        /// Days this option plots, or nil to follow the History window.
        public var days: Int? {
            switch self {
            case .historyWindow: nil
            case .days7: 7
            case .days30: 30
            case .days90: 90
            }
        }
    }

    public enum Style: String, CaseIterable, Equatable, Sendable {
        case bars
        case line
    }

    /// `UserDefaults` key of the stored dictionary; it lives outside the synced config like other chart choices.
    public static let defaultsKey = "chartPreferences"
    public static let standard = ChartPreferences()

    public var range: RangeOption
    public var stackByModel: Bool
    public var showsAverageLine: Bool
    public var style: Style
    public var paletteMode: ChartPaletteMode

    public init(
        range: RangeOption = .historyWindow,
        stackByModel: Bool = true,
        showsAverageLine: Bool = true,
        style: Style = .bars,
        paletteMode: ChartPaletteMode = .accents)
    {
        self.range = range
        self.stackByModel = stackByModel
        self.showsAverageLine = showsAverageLine
        self.style = style
        self.paletteMode = paletteMode
    }

    // MARK: - Range

    /// Days a chart plots: the chosen range, never more than the History window loaded.
    public func plottedDays(historyDays: Int) -> Int {
        let available = max(1, historyDays)
        guard let days = self.range.days else { return available }
        return min(days, available)
    }

    /// The entries a chart plots: the last `plottedDays` local days ending on `now`'s day. All of `entries`
    /// when the range follows the History window or covers all of it, so the default plots exactly as before.
    public func plottedEntries(
        _ entries: [CostUsageDailyReport.Entry],
        historyDays: Int,
        now: Date,
        calendar: Calendar) -> [CostUsageDailyReport.Entry]
    {
        let days = self.plottedDays(historyDays: historyDays)
        guard days < max(1, historyDays) else { return entries }
        return CostReportingPeriod.rolling(days: days).entries(entries, now: now, calendar: calendar)
    }

    // MARK: - Storage

    private enum StorageKey {
        static let range = "range"
        static let stackByModel = "stackByModel"
        static let averageLine = "averageLine"
        static let style = "style"
        static let palette = "palette"
    }

    /// Reads the stored dictionary; missing or unknown values keep their defaults.
    public init(storage: [String: String]?) {
        let storage = storage ?? [:]
        self.init(
            range: storage[StorageKey.range].flatMap(RangeOption.init(rawValue:)) ?? .historyWindow,
            stackByModel: Self.bool(storage[StorageKey.stackByModel]) ?? true,
            showsAverageLine: Self.bool(storage[StorageKey.averageLine]) ?? true,
            style: storage[StorageKey.style].flatMap(Style.init(rawValue:)) ?? .bars,
            paletteMode: storage[StorageKey.palette].flatMap(ChartPaletteMode.init(rawValue:)) ?? .accents)
    }

    /// The dictionary stored in `UserDefaults`.
    public var storage: [String: String] {
        [
            StorageKey.range: self.range.rawValue,
            StorageKey.stackByModel: self.stackByModel ? "true" : "false",
            StorageKey.averageLine: self.showsAverageLine ? "true" : "false",
            StorageKey.style: self.style.rawValue,
            StorageKey.palette: self.paletteMode.rawValue,
        ]
    }

    private static func bool(_ raw: String?) -> Bool? {
        switch raw {
        case "true": true
        case "false": false
        default: nil
        }
    }
}
