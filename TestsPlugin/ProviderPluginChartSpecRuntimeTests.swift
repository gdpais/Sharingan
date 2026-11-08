import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SharinganCore

struct ProviderPluginChartSpecRuntimeTests {
    private typealias Chart = ProviderDetailSection.Chart

    @Test(arguments: BundledPluginTestSupport.engines)
    func `v1 chart payloads map exactly as before`(engine: ProviderPluginEngineKind) async throws {
        let chart = try await Self.chart(engine: engine, fields: """
        kind: "line", title: " Daily ", unit: "USD",
        points: [{ label: " Mon ", value: 1.5 }, { label: "Mon", value: -2 }],
        """)

        #expect(try chart == Chart(
            kind: .line,
            title: "Daily",
            unit: "USD",
            points: [Chart.Point(label: "Mon", value: 1.5), Chart.Point(label: "Mon", value: -2)]))
        #expect(chart.series.isEmpty)
        #expect(chart.references.isEmpty)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `v2 stacked series and references map and ignore unknown keys`(engine: ProviderPluginEngineKind) async throws {
        let chart = try await Self.chart(engine: engine, fields: """
        kind: "bars", version: 2, title: "Daily tokens", unit: "tokens",
        series: [
          { name: " Input ", stack: "tokens", color: "red",
            points: [{ label: "Mon", value: 3 }, { label: "Tue", value: 4, note: "ignored" }] },
          { name: "Output", stack: "tokens", points: [{ label: "Tue", value: 1 }] },
          { name: "Retries", stack: null, points: [{ label: "Wed", value: 2 }] },
        ],
        references: [
          { value: 10, label: " Cap ", style: "solid", extra: true },
          { value: 6.5, label: null },
        ],
        """)

        #expect(chart.points.isEmpty)
        #expect(chart.series.map(\.name) == ["Input", "Output", "Retries"])
        #expect(chart.series.map(\.stack) == ["tokens", "tokens", nil])
        #expect(try chart.series[0].points == [
            Chart.Point(label: "Mon", value: 3),
            Chart.Point(label: "Tue", value: 4),
        ])
        #expect(try chart.references == [
            Chart.Reference(value: 10, label: "Cap", style: .solid),
            Chart.Reference(value: 6.5, style: .dashed),
        ])
        #expect(chart.seriesLabels == ["Mon", "Tue", "Wed"])
    }

    @Test
    func `series keep the points fallback for older hosts`() async throws {
        let chart = try await Self.chart(fields: """
        kind: "line",
        points: [{ label: "Mon", value: 5 }],
        series: [{ name: "A", points: [{ label: "Mon", value: 2 }] }, { name: "B", points: [] }],
        references: [],
        """)

        #expect(try chart.points == [Chart.Point(label: "Mon", value: 5)])
        #expect(chart.series.map(\.points.count) == [1, 0])
        #expect(chart.references.isEmpty)
    }

    @Test
    func `references alone extend a single series chart`() async throws {
        let chart = try await Self.chart(fields: """
        kind: "bars", points: [{ label: "Mon", value: 5 }], references: [{ value: 8, label: "Budget" }],
        """)

        #expect(chart.series.isEmpty)
        #expect(try chart.references == [Chart.Reference(value: 8, label: "Budget")])
    }

    @Test(arguments: [
        // Shape
        #"kind: "bars", series: {}"#,
        #"kind: "bars", series: []"#,
        #"kind: "bars""#,
        #"kind: "bars", points: 3, series: [{ name: "A", points: [] }]"#,
        #"kind: "bars", series: [1]"#,
        #"kind: "bars", series: [{ points: [] }]"#,
        #"kind: "bars", series: [{ name: 3, points: [] }]"#,
        #"kind: "bars", series: [{ name: "A", stack: 1, points: [] }]"#,
        #"kind: "bars", series: [{ name: "A" }]"#,
        #"kind: "bars", series: [{ name: "A", points: [{ label: "x" }] }]"#,
        #"kind: "bars", points: [], references: {}"#,
        #"kind: "bars", points: [], references: [3]"#,
        #"kind: "bars", points: [], references: [{ label: "Cap" }]"#,
        #"kind: "bars", points: [], references: [{ value: "10" }]"#,
        #"kind: "bars", points: [], references: [{ value: 10, style: "dotted" }]"#,
        #"kind: "bars", points: [], references: [{ value: 10, style: 1 }]"#,
        // Values
        #"kind: "bars", series: [{ name: "A", points: [{ label: "x", value: NaN }] }]"#,
        #"kind: "bars", series: [{ name: "A", points: [{ label: "x", value: Infinity }] }]"#,
        #"kind: "bars", points: [], references: [{ value: NaN }]"#,
        #"kind: "bars", points: [], references: [{ value: -Infinity }]"#,
        #"kind: "bars", series: [{ name: "A", points: [{ label: "x", value: 1 }, { label: " x ", value: 2 }] }]"#,
        // Limits
        #"kind: "bars", series: Array.from({ length: 9 }, (_, i) => ({ name: "S" + i, points: [] }))"#,
        #"kind: "bars", points: [], references: Array.from({ length: 5 }, (_, i) => ({ value: i }))"#,
        #"kind: "bars", series: [{ name: "A", points: numbered(0, 121) }]"#,
        #"kind: "bars", series: [{ name: "A", points: numbered(0, 61) }, { name: "B", points: numbered(61, 60) }]"#,
        #"kind: "bars", series: [{ name: "x".repeat(121), points: [] }]"#,
    ])
    func `invalid series and references fail the fetch`(fields: String) async throws {
        let runtime = try ProviderPluginRuntime(source: Self.plugin(chartFields: fields))

        await #expect(throws: ProviderPluginError.self) {
            _ = try await runtime.fetchUsage(secrets: ["TEST_KEY": "fixture"])
        }
    }

    // MARK: - Fixtures

    private static func chart(
        engine: ProviderPluginEngineKind = .automatic,
        fields: String) async throws -> Chart
    {
        let runtime = try ProviderPluginRuntime(source: Self.plugin(chartFields: fields), engine: engine)
        let snapshot = try await runtime.fetchUsage(secrets: ["TEST_KEY": "fixture"])
        return try #require(snapshot.details.first?.chart)
    }

    /// Chart fields may call `numbered(start, count)` for `count` points labelled from `start`.
    private static func plugin(chartFields: String) -> String {
        """
        defineProvider({
          id: "synthetic",
          name: "Fixture",
          endpoints: ["https://api.example.test"],
          auth: { type: "bearer", secret: "TEST_KEY" },
          settings: [{ key: "TEST_KEY", title: "API key", type: "secure" }],
          async fetchUsage(ctx) {
            const numbered = (start, count) =>
              Array.from({ length: count }, (_, i) => ({ label: String(start + i), value: i }));
            return { details: [{ rows: [], chart: { \(chartFields) } }] };
          },
        });
        """
    }
}
