import Foundation
import SharinganCore

extension CLIRenderer {
    /// One `label: value` line of a provider detail chart in text output.
    struct ChartTextLine: Equatable {
        let label: String
        let value: String
    }

    /// Text lines for chart spec v2: every series point as `Title · Series · Label`, then every reference line as
    /// `Title · Reference · Label`. Empty for single-series charts, whose `points` render on their own.
    static func chartSeriesTextLines(_ chart: ProviderDetailSection.Chart) -> [ChartTextLine] {
        let unit = chart.unit.map { " \($0)" } ?? ""
        var lines: [ChartTextLine] = []
        for series in chart.series {
            for point in series.points {
                lines.append(ChartTextLine(
                    label: [chart.title, series.name, point.label].compactMap(\.self).joined(separator: " · "),
                    value: "\(point.value.formatted())\(unit)"))
            }
        }
        for reference in chart.references {
            lines.append(ChartTextLine(
                label: [chart.title, "Reference", reference.label].compactMap(\.self).joined(separator: " · "),
                value: "\(reference.value.formatted())\(unit)"))
        }
        return lines
    }
}
