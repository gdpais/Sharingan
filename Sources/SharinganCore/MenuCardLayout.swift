import Foundation

// MARK: - Section and chart kinds

/// A part of a provider's menu card that the card builder can reorder or hide.
public enum MenuCardSectionKind: String, CaseIterable, Codable, Sendable {
    case usage
    case pace
    case chart
    case credits
    case extraUsage
    case cost

    /// Today's card, top to bottom. New kinds go here, at the place they take in the built-in card.
    public static let defaultOrder: [MenuCardSectionKind] = [.usage, .pace, .chart, .credits, .extraUsage, .cost]

    /// Pace is drawn inside the usage rows, so it can be hidden but has no position of its own.
    public var isReorderable: Bool {
        self != .pace
    }
}

/// The chart a card draws in its chart slot.
public enum MenuCardChartChoice: String, CaseIterable, Codable, Sendable {
    /// Today's behavior: the provider's data decides (Live, Spend, or the Live/Spend switch).
    case automatic
    case live
    case spend
    case burndown
    case planFit
    case none

    /// Charts that need data a provider may not have.
    public static let dataCharts: [MenuCardChartChoice] = [.live, .spend, .burndown, .planFit]
}

/// A provider menu link the card builder can hide.
public enum MenuCardMenuItem: String, CaseIterable, Codable, Sendable {
    case usageDashboard
    case statusPage
}

// MARK: - Availability and resolution

/// What a provider can show right now. Resolution drops everything outside it.
public struct MenuCardLayoutAvailability: Equatable, Sendable {
    public var sections: Set<MenuCardSectionKind>
    /// Concrete charts with data; `automatic` and `none` are never listed.
    public var charts: Set<MenuCardChartChoice>

    public init(sections: Set<MenuCardSectionKind>, charts: Set<MenuCardChartChoice>) {
        self.sections = sections
        self.charts = charts
    }

    public static let everything = MenuCardLayoutAvailability(
        sections: Set(MenuCardSectionKind.allCases),
        charts: Set(MenuCardChartChoice.dataCharts))
}

/// A layout narrowed to one provider's data.
public struct MenuCardResolvedLayout: Equatable, Sendable {
    /// Visible sections the provider can show, in display order. `chart` is listed only with a chart to draw.
    public let sections: [MenuCardSectionKind]
    /// `automatic`, a concrete chart the provider has data for, or `none`. Never another provider's chart.
    public let chart: MenuCardChartChoice
    /// True when the reorderable sections keep their default relative order, so the built-in card applies.
    public let usesDefaultOrder: Bool

    public init(sections: [MenuCardSectionKind], chart: MenuCardChartChoice, usesDefaultOrder: Bool) {
        self.sections = sections
        self.chart = chart
        self.usesDefaultOrder = usesDefaultOrder
    }

    public func contains(_ kind: MenuCardSectionKind) -> Bool {
        self.sections.contains(kind)
    }
}

// MARK: - Layout

/// Per-provider order and visibility of menu card sections, the card's chart, and hidden menu links.
///
/// `default` reproduces today's card. Stored layouts are normalized on the way in: unknown kinds are dropped,
/// duplicates keep their first place, and kinds the stored layout predates are inserted at their default place.
public struct MenuCardLayout: Equatable, Sendable {
    public struct Section: Hashable, Sendable {
        public let kind: MenuCardSectionKind
        public var isVisible: Bool

        public init(kind: MenuCardSectionKind, isVisible: Bool = true) {
            self.kind = kind
            self.isVisible = isVisible
        }
    }

    /// Every known kind exactly once, in display order.
    public private(set) var sections: [Section]
    public var chart: MenuCardChartChoice
    public var hiddenMenuItems: Set<MenuCardMenuItem>

    public init(
        sections: [Section] = MenuCardSectionKind.defaultOrder.map { Section(kind: $0) },
        chart: MenuCardChartChoice = .automatic,
        hiddenMenuItems: Set<MenuCardMenuItem> = [])
    {
        self.sections = Self.normalizedSections(sections)
        self.chart = chart
        self.hiddenMenuItems = hiddenMenuItems
    }

    public static let `default` = MenuCardLayout()

    public var isDefault: Bool {
        self == Self.default
    }

    /// The card itself is today's; only menu links may differ.
    public var hasDefaultCard: Bool {
        self.sections == Self.default.sections && self.chart == .automatic
    }

    public var order: [MenuCardSectionKind] {
        self.sections.map(\.kind)
    }

    public var reorderableSections: [Section] {
        self.sections.filter(\.kind.isReorderable)
    }

    public func isVisible(_ kind: MenuCardSectionKind) -> Bool {
        self.sections.first { $0.kind == kind }?.isVisible ?? true
    }

    public mutating func setVisible(_ isVisible: Bool, for kind: MenuCardSectionKind) {
        guard let index = self.sections.firstIndex(where: { $0.kind == kind }) else { return }
        self.sections[index].isVisible = isVisible
    }

    public func showsMenuItem(_ item: MenuCardMenuItem) -> Bool {
        !self.hiddenMenuItems.contains(item)
    }

    public mutating func setMenuItem(_ item: MenuCardMenuItem, visible: Bool) {
        if visible {
            self.hiddenMenuItems.remove(item)
        } else {
            self.hiddenMenuItems.insert(item)
        }
    }

    /// Whether `kind` can move `offset` steps among the reorderable sections.
    public func canMove(_ kind: MenuCardSectionKind, by offset: Int) -> Bool {
        let kinds = self.reorderableSections.map(\.kind)
        guard let index = kinds.firstIndex(of: kind) else { return false }
        return kinds.indices.contains(index + offset)
    }

    /// Moves a reorderable section `offset` steps among the reorderable sections; pace keeps its slot.
    @discardableResult
    public mutating func move(_ kind: MenuCardSectionKind, by offset: Int) -> Bool {
        guard offset != 0, self.canMove(kind, by: offset) else { return false }
        var movable = self.reorderableSections
        guard let index = movable.firstIndex(where: { $0.kind == kind }) else { return false }
        let section = movable.remove(at: index)
        movable.insert(section, at: index + offset)
        var iterator = movable.makeIterator()
        self.sections = self.sections.map { section in
            guard section.kind.isReorderable else { return section }
            return iterator.next() ?? section
        }
        return true
    }

    /// Narrows the layout to what a provider can show. Hidden or unavailable sections drop out; a chosen chart
    /// without data becomes `none` rather than falling back to some other chart.
    public func resolved(for availability: MenuCardLayoutAvailability) -> MenuCardResolvedLayout {
        let chart = self.resolvedChart(for: availability)
        let sections = self.sections.compactMap { section -> MenuCardSectionKind? in
            guard section.isVisible else { return nil }
            if section.kind == .chart {
                return chart == .none ? nil : .chart
            }
            return availability.sections.contains(section.kind) ? section.kind : nil
        }
        let reorderable = sections.filter(\.isReorderable)
        let defaultRelativeOrder = MenuCardSectionKind.defaultOrder.filter { reorderable.contains($0) }
        return MenuCardResolvedLayout(
            sections: sections,
            chart: chart,
            usesDefaultOrder: reorderable == defaultRelativeOrder)
    }

    private func resolvedChart(for availability: MenuCardLayoutAvailability) -> MenuCardChartChoice {
        guard self.isVisible(.chart) else { return .none }
        switch self.chart {
        case .automatic:
            let hasBuiltInChart = availability.charts.contains(.live) || availability.charts.contains(.spend)
            return hasBuiltInChart ? .automatic : .none
        case .none:
            return .none
        case .live, .spend, .burndown, .planFit:
            return availability.charts.contains(self.chart) ? self.chart : .none
        }
    }

    // MARK: Normalization

    /// Known kinds once each, in stored order; kinds missing from `stored` go after their nearest default
    /// predecessor that is present, or first when none is.
    public static func normalizedSections(_ stored: [Section]) -> [Section] {
        var result: [Section] = []
        var seen: Set<MenuCardSectionKind> = []
        for section in stored where seen.insert(section.kind).inserted {
            result.append(section)
        }
        let defaultOrder = MenuCardSectionKind.defaultOrder
            + MenuCardSectionKind.allCases.filter { !MenuCardSectionKind.defaultOrder.contains($0) }
        for (defaultIndex, kind) in defaultOrder.enumerated() where !seen.contains(kind) {
            var insertionIndex = 0
            for predecessor in defaultOrder[..<defaultIndex].reversed() {
                if let index = result.firstIndex(where: { $0.kind == predecessor }) {
                    insertionIndex = index + 1
                    break
                }
            }
            result.insert(Section(kind: kind), at: insertionIndex)
            seen.insert(kind)
        }
        return result
    }
}

// MARK: - Codable

extension MenuCardLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case sections
        case chart
        case hiddenMenuItems
    }

    /// One stored section; malformed entries and unknown kinds decode as nil instead of failing the layout.
    private struct StoredSection: Codable {
        let kind: MenuCardSectionKind?
        let isVisible: Bool

        private enum CodingKeys: String, CodingKey {
            case kind
            case visible
        }

        init(_ section: Section) {
            self.kind = section.kind
            self.isVisible = section.isVisible
        }

        init(from decoder: any Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            let rawKind = container.flatMap { try? $0.decode(String.self, forKey: .kind) }
            self.kind = rawKind.flatMap(MenuCardSectionKind.init(rawValue:))
            self.isVisible = container.flatMap { try? $0.decode(Bool.self, forKey: .visible) } ?? true
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(self.kind?.rawValue, forKey: .kind)
            try container.encode(self.isVisible, forKey: .visible)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = (try? container.decode([StoredSection].self, forKey: .sections)) ?? []
        let sections = stored.compactMap { entry in
            entry.kind.map { Section(kind: $0, isVisible: entry.isVisible) }
        }
        let rawChart = try? container.decode(String.self, forKey: .chart)
        let rawItems = (try? container.decode([String].self, forKey: .hiddenMenuItems)) ?? []
        self.init(
            sections: sections,
            chart: rawChart.flatMap(MenuCardChartChoice.init(rawValue:)) ?? .automatic,
            hiddenMenuItems: Set(rawItems.compactMap(MenuCardMenuItem.init(rawValue:))))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.sections.map { StoredSection($0) }, forKey: .sections)
        try container.encode(self.chart.rawValue, forKey: .chart)
        try container.encode(self.hiddenMenuItems.map(\.rawValue).sorted(), forKey: .hiddenMenuItems)
    }

    /// The layout stored in `json`, or nil when it is not a layout object at all.
    public static func decoded(fromJSON json: String) -> MenuCardLayout? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MenuCardLayout.self, from: data)
    }

    /// Stable JSON for persistence: sorted keys, menu items sorted.
    public func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
