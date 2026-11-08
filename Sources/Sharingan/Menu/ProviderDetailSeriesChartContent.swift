import Charts
import SharinganCore
import SwiftUI

/// Plot for provider detail charts that use chart spec v2 series or reference lines.
///
/// The caller fixes the height, as for the single-series renderers. Series take `ChartPalette` slots
/// in series order; a single series keeps the provider color. Reference lines and their labels use
/// label colors, never series colors.
struct ProviderDetailSeriesChartPlot: View {
    let chart: ProviderDetailSection.Chart
    let color: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let layout = ProviderDetailChartLayout(chart: self.chart)
        Chart {
            ForEach(Array(layout.segments.enumerated()), id: \.offset) { _, segment in
                self.mark(segment, layout: layout)
            }
            ForEach(Array(layout.rules.enumerated()), id: \.offset) { _, rule in
                RuleMark(y: .value(L("Usage"), rule.value))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineStyle(Self.strokeStyle(rule.style))
                    .annotation(
                        position: .top,
                        alignment: .leading,
                        overflowResolution: .init(x: .fit, y: .fit))
                    {
                        if let label = rule.label {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                                .lineLimit(1)
                        }
                    }
            }
        }
        .chartXScale(domain: layout.xDomain)
        .chartYScale(domain: 0...Self.ceiling(for: layout.maximum))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(MenuHighlightStyle.secondary(self.isHighlighted).opacity(0.22))
                .frame(height: 1)
        }
    }

    @ChartContentBuilder
    private func mark(
        _ segment: ProviderDetailChartLayout.Segment,
        layout: ProviderDetailChartLayout) -> some ChartContent
    {
        if layout.kind == .bars {
            RectangleMark(
                xStart: .value(L("Label"), segment.xStart),
                xEnd: .value(L("Label"), segment.xEnd),
                yStart: .value(L("Usage"), segment.yStart),
                yEnd: .value(L("Usage"), segment.yEnd))
                .foregroundStyle(self.seriesColor(segment.series, count: layout.series.count))
        } else if layout.series[segment.series].isStacked {
            AreaMark(
                x: .value(L("Label"), segment.xStart),
                yStart: .value(L("Usage"), segment.yStart),
                yEnd: .value(L("Usage"), segment.yEnd),
                series: .value(L("Series"), segment.series))
                .foregroundStyle(self.seriesColor(segment.series, count: layout.series.count).opacity(0.8))
        } else {
            LineMark(
                x: .value(L("Label"), segment.xStart),
                y: .value(L("Usage"), segment.yEnd),
                series: .value(L("Series"), segment.series))
                .foregroundStyle(self.seriesColor(segment.series, count: layout.series.count))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                // Dots like the single-series line renderer, so a one-point series is still visible.
                .symbol(.circle)
                .symbolSize(9)
        }
    }

    private func seriesColor(_ index: Int, count: Int) -> Color {
        guard count > 1 else {
            return self.isHighlighted ? MenuHighlightStyle.selectionText : self.color
        }
        return ChartPalette.color(for: .index(index))
    }

    private static func strokeStyle(_ style: ProviderDetailSection.Chart.Reference.Style) -> StrokeStyle {
        switch style {
        case .solid: StrokeStyle(lineWidth: 1)
        case .dashed: ChartReferenceLine.strokeStyle
        }
    }

    /// Top of the y domain: the 1-2-5 tick at or above the largest value, so references stay on scale.
    static func ceiling(for maximum: Double) -> Double {
        guard maximum.isFinite, maximum > 0 else { return 1 }
        guard let top = ChartNiceScale.ticks(maximum: maximum).last, top.isFinite, top >= maximum else {
            return maximum
        }
        return top
    }

    static func accessibilityLabel(for chart: ProviderDetailSection.Chart) -> String {
        let title = chart.title.map { "\($0): " } ?? ""
        let unit = chart.unit.map { " \($0)" } ?? ""
        var parts: [String] = []
        if chart.series.isEmpty {
            parts.append(chart.points.map { "\($0.label) \($0.value)\(unit)" }.joined(separator: ", "))
        } else {
            for series in chart.series {
                let points = series.points.map { "\($0.label) \($0.value)\(unit)" }.joined(separator: ", ")
                parts.append("\(series.name): \(points)")
            }
        }
        for reference in chart.references {
            parts.append([reference.label, "\(reference.value)\(unit)"].compactMap(\.self).joined(separator: " "))
        }
        return title + parts.joined(separator: "; ")
    }
}

/// Legend for multi-series detail charts: one swatch and name per series, in palette order.
///
/// Rows are a fixed height and the menu card width is fixed, so the legend height depends only on
/// the series count.
struct ProviderDetailSeriesChartLegend: View {
    let names: [String]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 84), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 2)
        {
            ForEach(Array(self.names.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 4) {
                    Circle()
                        .fill(ChartPalette.color(for: .index(index)))
                        .frame(width: 6, height: 6)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(height: 12)
            }
        }
        // The chart's accessibility label already names every series.
        .accessibilityHidden(true)
    }
}
