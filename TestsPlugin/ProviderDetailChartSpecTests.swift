import Foundation
import Testing
@testable import CodexBarCore

struct ProviderDetailChartSpecTests {
    private typealias Chart = ProviderDetailSection.Chart

    // MARK: - Codable

    @Test
    func `v1 chart JSON decodes unchanged and encodes without v2 keys`() throws {
        let legacy = #"{"kind":"bars","title":"Daily","unit":"USD","points":[{"label":"Mon","value":1.5}]}"#
        let chart = try JSONDecoder().decode(Chart.self, from: Data(legacy.utf8))

        #expect(try chart == Chart(
            kind: .bars,
            title: "Daily",
            unit: "USD",
            points: [Chart.Point(label: "Mon", value: 1.5)]))
        #expect(chart.series.isEmpty)
        #expect(chart.references.isEmpty)
        #expect(try Self.keys(of: chart) == ["kind", "points", "title", "unit"])
    }

    @Test
    func `v1 chart JSON without points still fails to decode`() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Chart.self, from: Data(#"{"kind":"line"}"#.utf8))
        }
    }

    @Test
    func `v2 chart round trips and decodes without points`() throws {
        let chart = try Self.stackedChart()
        let decoded = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
        #expect(decoded == chart)
        #expect(try Self.keys(of: chart) == ["kind", "points", "references", "series", "title"])

        let seriesOnly = """
        {"kind":"line","series":[{"name":"Input","stack":"tokens","points":[{"label":"Mon","value":2}]}],
         "references":[{"value":4}]}
        """
        let minimal = try JSONDecoder().decode(Chart.self, from: Data(seriesOnly.utf8))
        #expect(minimal.points.isEmpty)
        #expect(minimal.series.map(\.stack) == ["tokens"])
        #expect(try minimal.references == [Chart.Reference(value: 4, style: .dashed)])
    }

    // MARK: - Validation

    @Test
    func `series and reference limits accept the maximum and reject one more`() throws {
        let point = try Chart.Point(label: "Mon", value: 1)
        let series = try (0..<8).map { try Chart.Series(name: "S\($0)", points: [point]) }
        let references = try (0..<4).map { try Chart.Reference(value: Double($0)) }
        let chart = try Chart(kind: .bars, points: [], series: series, references: references)
        #expect(chart.series.count == ProviderDetailSection.maximumSeriesPerChart)
        #expect(chart.references.count == ProviderDetailSection.maximumReferencesPerChart)

        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart(kind: .bars, points: [], series: series + [series[0]])
        }
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart(kind: .bars, points: [], references: references + [references[0]])
        }
    }

    @Test
    func `series share at most the single chart label budget`() throws {
        let first = try Chart.Series(name: "A", points: Self.numberedPoints(0..<60))
        let second = try Chart.Series(name: "B", points: Self.numberedPoints(60..<120))
        let overlapping = try Chart.Series(name: "C", points: Self.numberedPoints(0..<120))
        let chart = try Chart(kind: .line, points: [], series: [first, second, overlapping])
        #expect(chart.seriesLabels.count == 120)

        let extra = try Chart.Series(name: "D", points: [Chart.Point(label: "120", value: 1)])
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart(kind: .line, points: [], series: [first, second, extra])
        }
    }

    @Test
    func `series reject repeated labels oversized point lists and empty names`() throws {
        let point = try Chart.Point(label: "Mon", value: 1)
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart.Series(name: "A", points: [point, Chart.Point(label: " Mon ", value: 2)])
        }
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart.Series(name: "A", points: Self.numberedPoints(0..<121))
        }
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart.Series(name: "  ", points: [point])
        }
        let trimmed = try Chart.Series(name: " Input ", stack: "  ", points: [point])
        #expect(trimmed.name == "Input")
        #expect(trimmed.stack == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func `references and series points reject nonfinite values`(value: Double) {
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart.Reference(value: value)
        }
        #expect(throws: ProviderDetailSection.ValidationError.self) {
            _ = try Chart.Point(label: "Mon", value: value)
        }
    }

    @Test
    func `text mapping rewrites labels and drops series whose labels collapse`() throws {
        let series = try Chart.Series(name: "a@example.com", stack: "s", points: [
            Chart.Point(label: "a@example.com", value: 1),
            Chart.Point(label: "Tue", value: 2),
        ])
        let redacted = try #require(series.mappingText { $0.replacingOccurrences(of: "a@example.com", with: "Pool") })
        #expect(redacted.name == "Pool")
        #expect(redacted.stack == "s")
        #expect(redacted.points.map(\.label) == ["Pool", "Tue"])
        #expect(series.mappingText { _ in "Same" } == nil)

        let reference = try Chart.Reference(value: 3, label: "Cap a@example.com", style: .solid)
        let mapped = try #require(reference.mappingText { $0.replacingOccurrences(of: " a@example.com", with: "") })
        #expect(try mapped == Chart.Reference(value: 3, label: "Cap", style: .solid))
    }

    // MARK: - Layout

    @Test
    func `v1 charts keep the single series renderers`() throws {
        let v1 = try Chart(kind: .bars, points: [Chart.Point(label: "Mon", value: 1)])
        #expect(!ProviderDetailChartLayout.usesSeriesRenderer(for: v1))
        #expect(try ProviderDetailChartLayout.usesSeriesRenderer(for: Self.stackedChart()))
        let withReference = try Chart(
            kind: .bars,
            points: [Chart.Point(label: "Mon", value: 1)],
            references: [Chart.Reference(value: 2)])
        #expect(ProviderDetailChartLayout.usesSeriesRenderer(for: withReference))
    }

    @Test
    func `stacked bars accumulate per stack and other series get their own bar`() throws {
        let layout = try ProviderDetailChartLayout(chart: Self.stackedChart())

        #expect(layout.labels == ["Mon", "Tue", "Wed"])
        #expect(layout.groupCount == 2)
        #expect(layout.series.map(\.isStacked) == [true, true, false])
        #expect(layout.showsLegend)
        let ranges = layout.segments.map { [Double($0.series), Double($0.slot), $0.yStart, $0.yEnd] }
        #expect(ranges == [[0, 0, 0, 3], [0, 1, 0, 4], [1, 1, 4, 5], [2, 2, 0, 2]])
        #expect(layout.maximum == 10)
        #expect(layout.rules.map(\.value) == [10, 6])
        #expect(layout.rules.map(\.style) == [.solid, .dashed])

        let stackBar = try #require(layout.segments.first { $0.series == 1 })
        let ownBar = try #require(layout.segments.first { $0.series == 2 })
        #expect(stackBar.xEnd <= 1)
        #expect(stackBar.xStart >= 1 - ProviderDetailChartLayout.slotWidth / 2)
        #expect(ownBar.xStart >= 2)
        #expect(ownBar.xEnd <= 2 + ProviderDetailChartLayout.slotWidth / 2)
        #expect(layout.xDomain == -0.5...2.5)
    }

    @Test
    func `line charts stack areas over every slot and lines skip missing labels`() throws {
        let chart = try Chart(kind: .line, points: [], series: [
            Chart.Series(name: "A", stack: "s", points: [Chart.Point(label: "Mon", value: 1)]),
            Chart.Series(name: "B", stack: "s", points: [Chart.Point(label: "Tue", value: 2)]),
            Chart.Series(name: "C", points: [
                Chart.Point(label: "Mon", value: 5),
                Chart.Point(label: "Wed", value: -3),
            ]),
        ])
        let layout = ProviderDetailChartLayout(chart: chart)

        let bands = layout.segments.filter { $0.series < 2 }.map { [Double($0.slot), $0.yStart, $0.yEnd] }
        #expect(bands == [[0, 0, 1], [1, 0, 0], [2, 0, 0], [0, 1, 1], [1, 0, 2], [2, 0, 0]])
        let line = layout.segments.filter { $0.series == 2 }
        #expect(line.map(\.slot) == [0, 2])
        #expect(line.map(\.yEnd) == [5, 0])
        #expect(line.allSatisfy { $0.xStart == $0.xEnd && $0.xStart == Double($0.slot) })
        #expect(layout.maximum == 5)
    }

    @Test
    func `points with references form one unnamed series that keeps repeated labels`() throws {
        let chart = try Chart(
            kind: .bars,
            points: [Chart.Point(label: "Mon", value: 2), Chart.Point(label: "Mon", value: 0)],
            references: [Chart.Reference(value: -4, label: "Floor")])
        let layout = ProviderDetailChartLayout(chart: chart)

        #expect(layout.labels == ["Mon", "Mon"])
        #expect(layout.series == [ProviderDetailChartLayout.Series(index: 0, name: nil, isStacked: false)])
        #expect(!layout.showsLegend)
        #expect(layout.segments.count == 1)
        #expect(layout.segments.first?.xStart == -ProviderDetailChartLayout.slotWidth / 2)
        #expect(layout.rules == [ProviderDetailChartLayout.Rule(value: 0, label: "Floor", style: .dashed)])
        #expect(layout.maximum == 2)
    }

    // MARK: - Fixtures

    private static func stackedChart() throws -> Chart {
        try Chart(
            kind: .bars,
            title: "Daily tokens",
            points: [],
            series: [
                Chart.Series(name: "Input", stack: "tokens", points: [
                    Chart.Point(label: "Mon", value: 3),
                    Chart.Point(label: "Tue", value: 4),
                ]),
                Chart.Series(name: "Output", stack: "tokens", points: [Chart.Point(label: "Tue", value: 1)]),
                Chart.Series(name: "Retries", points: [Chart.Point(label: "Wed", value: 2)]),
            ],
            references: [
                Chart.Reference(value: 10, label: "Cap", style: .solid),
                Chart.Reference(value: 6),
            ])
    }

    private static func numberedPoints(_ range: Range<Int>) throws -> [Chart.Point] {
        try range.map { try Chart.Point(label: "\($0)", value: 1) }
    }

    private static func keys(of chart: Chart) throws -> [String] {
        let data = try JSONEncoder().encode(chart)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return object.keys.sorted()
    }
}
