import Foundation

// MARK: - Chart spec v2 limits

extension ProviderDetailSection {
    /// One series per categorical `ChartPalette` slot, so every series keeps a distinct color.
    public static let maximumSeriesPerChart = 8
    public static let maximumReferencesPerChart = 4
}

// MARK: - Series and reference lines

extension ProviderDetailSection.Chart {
    /// One named series of a multi-series chart (chart spec v2).
    ///
    /// Series align by point label. Series that share a `stack` id draw stacked; a series without one
    /// draws on its own (its own bar in a bar chart, an overlaid line in a line chart).
    public struct Series: Codable, Equatable, Sendable {
        public let name: String
        public let stack: String?
        public let points: [Point]

        public init(name: String, stack: String? = nil, points: [Point]) throws {
            guard points.count <= ProviderDetailSection.maximumPointsPerChart else {
                throw ProviderDetailSection.ValidationError(
                    "chart.series.points exceeds \(ProviderDetailSection.maximumPointsPerChart) entries")
            }
            // Series align by label, so a repeated label within one series would be ambiguous.
            guard Set(points.map(\.label)).count == points.count else {
                throw ProviderDetailSection.ValidationError("chart.series.points labels must be unique")
            }
            self.name = try ProviderDetailChartText.required(name, path: "chart.series.name")
            self.stack = try ProviderDetailChartText.optional(stack, path: "chart.series.stack")
            self.points = points
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case stack
            case points
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                name: container.decode(String.self, forKey: .name),
                stack: container.decodeIfPresent(String.self, forKey: .stack),
                points: container.decode([Point].self, forKey: .points))
        }
    }

    /// A horizontal reference line, such as a cap or a budget (chart spec v2).
    public struct Reference: Codable, Equatable, Sendable {
        public enum Style: String, Codable, Equatable, Sendable {
            case solid
            case dashed
        }

        public let value: Double
        public let label: String?
        public let style: Style

        public init(value: Double, label: String? = nil, style: Style = .dashed) throws {
            guard value.isFinite else {
                throw ProviderDetailSection.ValidationError("chart.reference.value must be finite")
            }
            self.value = value
            self.label = try ProviderDetailChartText.optional(label, path: "chart.reference.label")
            self.style = style
        }

        private enum CodingKeys: String, CodingKey {
            case value
            case label
            case style
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                value: container.decode(Double.self, forKey: .value),
                label: container.decodeIfPresent(String.self, forKey: .label),
                style: container.decodeIfPresent(Style.self, forKey: .style) ?? .dashed)
        }
    }

    /// Distinct point labels across every series, in first-appearance order.
    public var seriesLabels: [String] {
        var seen = Set<String>()
        var labels: [String] = []
        for entry in self.series {
            for point in entry.points where seen.insert(point.label).inserted {
                labels.append(point.label)
            }
        }
        return labels
    }

    static func validateSpecV2(series: [Series], references: [Reference]) throws {
        guard series.count <= ProviderDetailSection.maximumSeriesPerChart else {
            throw ProviderDetailSection.ValidationError(
                "chart.series exceeds \(ProviderDetailSection.maximumSeriesPerChart) entries")
        }
        guard references.count <= ProviderDetailSection.maximumReferencesPerChart else {
            throw ProviderDetailSection.ValidationError(
                "chart.references exceeds \(ProviderDetailSection.maximumReferencesPerChart) entries")
        }
        // The series share one x axis, which holds as many slots as a single-series chart.
        var labels = Set<String>()
        for entry in series {
            for point in entry.points {
                labels.insert(point.label)
            }
        }
        guard labels.count <= ProviderDetailSection.maximumPointsPerChart else {
            throw ProviderDetailSection.ValidationError(
                "chart.series exceeds \(ProviderDetailSection.maximumPointsPerChart) distinct labels")
        }
    }
}

// MARK: - Text rewriting

extension ProviderDetailSection.Chart.Series {
    /// A copy with `transform` applied to the name and every point label, for privacy redaction.
    /// Returns nil when the rewritten series no longer validates, for example after two labels collapse.
    public func mappingText(_ transform: (String) -> String) -> Self? {
        let points = self.points.compactMap { point in
            try? ProviderDetailSection.Chart.Point(label: transform(point.label), value: point.value)
        }
        guard points.count == self.points.count else { return nil }
        return try? Self(name: transform(self.name), stack: self.stack, points: points)
    }
}

extension ProviderDetailSection.Chart.Reference {
    /// A copy with `transform` applied to the label, for privacy redaction.
    public func mappingText(_ transform: (String) -> String) -> Self? {
        try? Self(value: self.value, label: self.label.map(transform), style: self.style)
    }
}

// MARK: - Validation helpers

/// Mirrors `ProviderDetailSection`'s private string rules: trimmed, at most `maximumStringLength` characters.
private enum ProviderDetailChartText {
    static func required(_ rawValue: String, path: String) throws -> String {
        guard let value = try self.optional(rawValue, path: path) else {
            throw ProviderDetailSection.ValidationError("\(path) must not be empty")
        }
        return value
    }

    static func optional(_ rawValue: String?, path: String) throws -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= ProviderDetailSection.maximumStringLength else {
            throw ProviderDetailSection.ValidationError(
                "\(path) exceeds \(ProviderDetailSection.maximumStringLength) characters")
        }
        return value.isEmpty ? nil : value
    }
}
