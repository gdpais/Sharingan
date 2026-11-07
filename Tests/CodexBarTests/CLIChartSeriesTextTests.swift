import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIChartSeriesTextTests {
    @Test
    func `text output lists chart series points and reference lines`() throws {
        let chart = try ProviderDetailSection.Chart(
            kind: .bars,
            title: "Daily tokens",
            unit: "tokens",
            points: [ProviderDetailSection.Chart.Point(label: "Mon", value: 150)],
            series: [
                ProviderDetailSection.Chart.Series(
                    name: "Input",
                    stack: "tokens",
                    points: [
                        ProviderDetailSection.Chart.Point(label: "Mon", value: 120),
                        ProviderDetailSection.Chart.Point(label: "Tue", value: 90),
                    ]),
                ProviderDetailSection.Chart.Series(
                    name: "Output",
                    points: [ProviderDetailSection.Chart.Point(label: "Mon", value: 30)]),
            ],
            references: [
                ProviderDetailSection.Chart.Reference(value: 200, label: "Daily cap", style: .solid),
                ProviderDetailSection.Chart.Reference(value: 140),
            ])

        #expect(CLIRenderer.chartSeriesTextLines(chart) == [
            .init(label: "Daily tokens · Input · Mon", value: "120 tokens"),
            .init(label: "Daily tokens · Input · Tue", value: "90 tokens"),
            .init(label: "Daily tokens · Output · Mon", value: "30 tokens"),
            .init(label: "Daily tokens · Reference · Daily cap", value: "200 tokens"),
            .init(label: "Daily tokens · Reference", value: "140 tokens"),
        ])

        let snapshot = try UsageSnapshot(
            primary: nil,
            secondary: nil,
            details: [ProviderDetailSection(title: "Usage", chart: chart)],
            updatedAt: Date(timeIntervalSince1970: 0))
        let text = CLIRenderer.renderText(
            provider: .deepgram,
            snapshot: snapshot,
            credits: nil,
            context: RenderContext(header: "Plugin", status: nil, useColor: false, resetStyle: .countdown))
        // The legacy fallback points stay first, so single-series consumers read the same lines as before.
        let lines = text.components(separatedBy: "\n")
        let fallback = try #require(lines.firstIndex(of: "Daily tokens · Mon: 150 tokens"))
        let firstSeries = try #require(lines.firstIndex(of: "Daily tokens · Input · Mon: 120 tokens"))
        #expect(fallback < firstSeries)
        #expect(lines.contains("Daily tokens · Reference · Daily cap: 200 tokens"))
    }

    @Test
    func `single series charts add no series lines`() throws {
        let chart = try ProviderDetailSection.Chart(
            kind: .line,
            title: "Spend",
            points: [ProviderDetailSection.Chart.Point(label: "Mon", value: 3)])

        #expect(CLIRenderer.chartSeriesTextLines(chart).isEmpty)
    }
}
