import Foundation

/// Plot geometry for provider detail charts that use chart spec v2 series or reference lines.
///
/// Slot `i` is centred on `x = i`. Values below zero draw at the baseline, as in the single-series
/// renderers. Charts without series or references never reach this layout: they keep the original
/// bar strip and line renderers so v1 payloads draw exactly as before.
public struct ProviderDetailChartLayout: Equatable, Sendable {
    public struct Series: Equatable, Sendable {
        /// Position in the chart's series order, which is also the series' palette slot.
        public let index: Int
        /// Legend name; nil for the unnamed series built from `points`.
        public let name: String?
        /// Stacked series draw as stacked bars or stacked areas.
        public let isStacked: Bool
    }

    /// One plotted value.
    ///
    /// Bar charts draw the rectangle `xStart...xEnd` × `yStart...yEnd`. Line charts use `xStart`
    /// (equal to `xEnd`): stacked series fill `yStart...yEnd` as an area band, other series draw a
    /// line through `yEnd`.
    public struct Segment: Equatable, Sendable {
        public let series: Int
        public let slot: Int
        public let xStart: Double
        public let xEnd: Double
        public let yStart: Double
        public let yEnd: Double
    }

    public struct Rule: Equatable, Sendable {
        /// Reference value clamped at the zero baseline.
        public let value: Double
        public let label: String?
        public let style: ProviderDetailSection.Chart.Reference.Style
    }

    /// Fraction of a slot covered by its bars; the rest separates neighbouring slots.
    public static let slotWidth = 0.8

    public let kind: ProviderDetailSection.Chart.Kind
    public let labels: [String]
    public let series: [Series]
    /// Bar groups per slot: one per stack id plus one per unstacked series.
    public let groupCount: Int
    public let segments: [Segment]
    public let rules: [Rule]
    /// Largest plotted value, including stack totals and reference lines; zero when nothing is positive.
    public let maximum: Double

    /// Whether a chart needs this layout instead of the single-series renderers.
    public static func usesSeriesRenderer(for chart: ProviderDetailSection.Chart) -> Bool {
        !chart.series.isEmpty || !chart.references.isEmpty
    }

    public var showsLegend: Bool {
        self.series.count > 1
    }

    public var xDomain: ClosedRange<Double> {
        -0.5...(Double(max(1, self.labels.count)) - 0.5)
    }

    public init(chart: ProviderDetailSection.Chart) {
        let inputs = Self.inputs(for: chart)
        self.kind = chart.kind
        self.labels = inputs.labels

        var groupByStack: [String: Int] = [:]
        var groupOfSeries: [Int] = []
        var groupCount = 0
        for entry in inputs.series {
            if let stack = entry.stack, let group = groupByStack[stack] {
                groupOfSeries.append(group)
                continue
            }
            if let stack = entry.stack {
                groupByStack[stack] = groupCount
            }
            groupOfSeries.append(groupCount)
            groupCount += 1
        }
        self.groupCount = groupCount
        self.series = inputs.series.enumerated().map { index, entry in
            Series(index: index, name: entry.name, isStacked: entry.stack != nil)
        }

        let groupWidth = Self.slotWidth / Double(max(1, groupCount))
        let inset = groupCount > 1 ? groupWidth * 0.06 : 0
        var stackTops: [Int: [Int: Double]] = [:]
        var segments: [Segment] = []
        var maximum = 0.0
        for (seriesIndex, entry) in inputs.series.enumerated() {
            let group = groupOfSeries[seriesIndex]
            let isStacked = entry.stack != nil
            for slot in inputs.labels.indices {
                let x = Double(slot)
                if chart.kind == .line, !isStacked {
                    // Lines skip missing labels and connect their neighbours.
                    guard let raw = entry.values[slot] else { continue }
                    let value = max(0, raw)
                    maximum = max(maximum, value)
                    segments.append(Segment(
                        series: seriesIndex, slot: slot, xStart: x, xEnd: x, yStart: 0, yEnd: value))
                    continue
                }
                let value = max(0, entry.values[slot] ?? 0)
                let base = isStacked ? stackTops[group]?[slot] ?? 0 : 0
                let top = min(base + value, Double.greatestFiniteMagnitude)
                if isStacked {
                    stackTops[group, default: [:]][slot] = top
                }
                maximum = max(maximum, top)
                switch chart.kind {
                case .bars:
                    guard value > 0 else { continue }
                    let start = x - Self.slotWidth / 2 + Double(group) * groupWidth
                    segments.append(Segment(
                        series: seriesIndex,
                        slot: slot,
                        xStart: start + inset,
                        xEnd: start + groupWidth - inset,
                        yStart: base,
                        yEnd: top))
                case .line:
                    // Stacked areas keep every slot, so a missing label is a zero-height band.
                    segments.append(Segment(
                        series: seriesIndex, slot: slot, xStart: x, xEnd: x, yStart: base, yEnd: top))
                }
            }
        }
        self.segments = segments

        let rules = chart.references.map { reference in
            Rule(value: max(0, reference.value), label: reference.label, style: reference.style)
        }
        for rule in rules {
            maximum = max(maximum, rule.value)
        }
        self.rules = rules
        self.maximum = maximum
    }

    // MARK: - Inputs

    private struct InputSeries {
        let name: String?
        let stack: String?
        /// Value per slot index; a missing slot means the series has no point with that label.
        let values: [Int: Double]
    }

    private struct Inputs {
        let labels: [String]
        let series: [InputSeries]
    }

    private static func inputs(for chart: ProviderDetailSection.Chart) -> Inputs {
        guard !chart.series.isEmpty else {
            // The `points` series keeps one slot per point, in order and with any repeated labels.
            var values: [Int: Double] = [:]
            for (index, point) in chart.points.enumerated() {
                values[index] = point.value
            }
            return Inputs(
                labels: chart.points.map(\.label),
                series: [InputSeries(name: nil, stack: nil, values: values)])
        }
        let labels = chart.seriesLabels
        var slotByLabel: [String: Int] = [:]
        for (slot, label) in labels.enumerated() {
            slotByLabel[label] = slot
        }
        let series = chart.series.map { entry -> InputSeries in
            var values: [Int: Double] = [:]
            for point in entry.points {
                guard let slot = slotByLabel[point.label] else { continue }
                values[slot] = point.value
            }
            return InputSeries(name: entry.name, stack: entry.stack, values: values)
        }
        return Inputs(labels: labels, series: series)
    }
}
