import Foundation

/// Chart spec v2: `series` and `references` on a detail chart.
///
/// The spec has no version marker; these fields are recognised by presence. Unknown keys inside a
/// chart, series, or reference are ignored like other unknown chart keys, and every present field
/// is validated with the same fail-the-fetch rules as `points`.
extension ProviderPluginSnapshotMapper {
    static func detailChartSeries(
        _ chart: any ProviderPluginValue,
        path: String) throws -> [ProviderDetailSection.Chart.Series]
    {
        guard let value = chart.property("series"), !value.isUndefined, !value.isNull else { return [] }
        guard value.isArray else {
            throw ProviderPluginError.invalidSnapshot("\(path).series must be an array")
        }
        let count = try self.boundedArrayCount(
            value,
            maximum: ProviderDetailSection.maximumSeriesPerChart,
            path: "\(path).series")
        var series: [ProviderDetailSection.Chart.Series] = []
        var labels = Set<String>()
        for index in 0..<count {
            let seriesPath = "\(path).series[\(index)]"
            guard let entry = value.element(at: index), entry.isObject, !entry.isArray else {
                throw ProviderPluginError.invalidSnapshot("\(seriesPath) must be an object")
            }
            let name = try self.requiredChartSpecString(entry, property: "name", path: seriesPath)
            let stack = try self.optionalChartSpecString(entry, property: "stack", path: seriesPath)
            guard let pointsValue = entry.property("points"), pointsValue.isArray else {
                throw ProviderPluginError.invalidSnapshot("\(seriesPath).points must be an array")
            }
            let points = try self.detailChartSeriesPoints(pointsValue, path: "\(seriesPath).points")
            for point in points {
                labels.insert(point.label)
            }
            try series.append(ProviderDetailSection.Chart.Series(name: name, stack: stack, points: points))
        }
        // All series share one x axis with as many slots as a single-series chart.
        guard labels.count <= ProviderDetailSection.maximumPointsPerChart else {
            throw ProviderPluginError.invalidSnapshot(
                "\(path).series exceeds \(ProviderDetailSection.maximumPointsPerChart) distinct labels")
        }
        return series
    }

    static func detailChartReferences(
        _ chart: any ProviderPluginValue,
        path: String) throws -> [ProviderDetailSection.Chart.Reference]
    {
        guard let value = chart.property("references"), !value.isUndefined, !value.isNull else { return [] }
        guard value.isArray else {
            throw ProviderPluginError.invalidSnapshot("\(path).references must be an array")
        }
        let count = try self.boundedArrayCount(
            value,
            maximum: ProviderDetailSection.maximumReferencesPerChart,
            path: "\(path).references")
        var references: [ProviderDetailSection.Chart.Reference] = []
        for index in 0..<count {
            let referencePath = "\(path).references[\(index)]"
            guard let entry = value.element(at: index), entry.isObject, !entry.isArray else {
                throw ProviderPluginError.invalidSnapshot("\(referencePath) must be an object")
            }
            let referenceValue = try self.requiredChartSpecNumber(entry, property: "value", path: referencePath)
            let label = try self.optionalChartSpecString(entry, property: "label", path: referencePath)
            var style = ProviderDetailSection.Chart.Reference.Style.dashed
            if let rawStyle = try self.optionalChartSpecString(entry, property: "style", path: referencePath) {
                guard let parsed = ProviderDetailSection.Chart.Reference.Style(rawValue: rawStyle) else {
                    throw ProviderPluginError.invalidSnapshot("\(referencePath).style must be 'solid' or 'dashed'")
                }
                style = parsed
            }
            try references.append(ProviderDetailSection.Chart.Reference(
                value: referenceValue,
                label: label,
                style: style))
        }
        return references
    }

    static func isAbsentDetailChartValue(_ value: (any ProviderPluginValue)?) -> Bool {
        guard let value else { return true }
        return value.isUndefined || value.isNull
    }

    // swiftlint:disable:next function_parameter_count
    static func assembleDetailChart(
        kind: ProviderDetailSection.Chart.Kind,
        title: String?,
        unit: String?,
        points: [ProviderDetailSection.Chart.Point],
        series: [ProviderDetailSection.Chart.Series],
        references: [ProviderDetailSection.Chart.Reference],
        path: String) throws -> ProviderDetailSection.Chart
    {
        do {
            return try ProviderDetailSection.Chart(
                kind: kind,
                title: title,
                unit: unit,
                points: points,
                series: series,
                references: references)
        } catch let error as ProviderDetailSection.ValidationError {
            throw ProviderPluginError.invalidSnapshot("\(path): \(error.message)")
        }
    }

    // MARK: - Values

    private static func detailChartSeriesPoints(
        _ value: any ProviderPluginValue,
        path: String) throws -> [ProviderDetailSection.Chart.Point]
    {
        let count = try self.boundedArrayCount(
            value,
            maximum: ProviderDetailSection.maximumPointsPerChart,
            path: path)
        var points: [ProviderDetailSection.Chart.Point] = []
        var labels = Set<String>()
        for index in 0..<count {
            let pointPath = "\(path)[\(index)]"
            guard let point = value.element(at: index), point.isObject, !point.isArray else {
                throw ProviderPluginError.invalidSnapshot("\(pointPath) must be an object")
            }
            let label = try self.requiredChartSpecString(point, property: "label", path: pointPath)
            // Series align by label, so each label may appear once per series.
            guard labels.insert(label).inserted else {
                throw ProviderPluginError.invalidSnapshot("\(pointPath).label repeats an earlier label")
            }
            try points.append(ProviderDetailSection.Chart.Point(
                label: label,
                value: self.requiredChartSpecNumber(point, property: "value", path: pointPath)))
        }
        return points
    }

    /// Same rules as the mapper's detail strings: trimmed, at most `maximumStringLength` characters.
    private static func optionalChartSpecString(
        _ value: any ProviderPluginValue,
        property: String,
        path: String) throws -> String?
    {
        guard let propertyValue = value.property(property),
              !propertyValue.isUndefined,
              !propertyValue.isNull
        else { return nil }
        guard propertyValue.isString else {
            throw ProviderPluginError.invalidSnapshot("\(path).\(property) must be a string")
        }
        let string = propertyValue.stringValue().trimmingCharacters(in: .whitespacesAndNewlines)
        guard string.count <= ProviderDetailSection.maximumStringLength else {
            throw ProviderPluginError.invalidSnapshot(
                "\(path).\(property) exceeds \(ProviderDetailSection.maximumStringLength) characters")
        }
        return string.isEmpty ? nil : string
    }

    private static func requiredChartSpecString(
        _ value: any ProviderPluginValue,
        property: String,
        path: String) throws -> String
    {
        guard let string = try self.optionalChartSpecString(value, property: property, path: path) else {
            throw ProviderPluginError.invalidSnapshot("\(path).\(property) is required")
        }
        return string
    }

    /// Rejects missing, non-number, NaN, and infinite values.
    private static func requiredChartSpecNumber(
        _ value: any ProviderPluginValue,
        property: String,
        path: String) throws -> Double
    {
        guard let propertyValue = value.property(property),
              !propertyValue.isUndefined,
              !propertyValue.isNull
        else {
            throw ProviderPluginError.invalidSnapshot("\(path).\(property) is required")
        }
        guard propertyValue.isNumber else {
            throw ProviderPluginError.invalidSnapshot("\(path).\(property) must be a number")
        }
        let number = propertyValue.doubleValue()
        guard number.isFinite else {
            throw ProviderPluginError.invalidSnapshot("\(path).\(property) must be finite")
        }
        return number
    }
}
