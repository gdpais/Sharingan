import AppKit
import SharinganCore
import SwiftUI
import Testing
@testable import Sharingan

@MainActor
struct ProviderDetailSeriesChartContentTests {
    private typealias Chart = ProviderDetailSection.Chart

    @Test
    func `series charts keep the plot height and add a legend only for several series`() throws {
        let v1 = try Self.height(of: Chart(kind: .bars, title: "Daily", points: [Chart.Point(label: "Mon", value: 2)]))
        let withReference = try Self.height(of: Chart(
            kind: .bars,
            title: "Daily",
            points: [Chart.Point(label: "Mon", value: 2)],
            references: [Chart.Reference(value: 3, label: "Cap")]))
        let oneSeries = try Self.height(of: Self.seriesChart(names: ["Input"], kind: .line))
        let threeSeries = try Self.height(of: Self.seriesChart(names: ["Input", "Output", "Retries"], kind: .bars))
        let renamed = try Self.height(of: Self.seriesChart(names: ["A", "B", "C"], kind: .line))

        #expect(withReference == v1)
        #expect(oneSeries == v1)
        #expect(threeSeries > v1)
        #expect(renamed == threeSeries)
    }

    @Test
    func `y ceiling follows 1 2 5 ticks and never drops below the data`() {
        #expect(ProviderDetailSeriesChartPlot.ceiling(for: 0) == 1)
        #expect(ProviderDetailSeriesChartPlot.ceiling(for: 7) == 8)
        #expect(ProviderDetailSeriesChartPlot.ceiling(for: 10) == 10)
        #expect(ProviderDetailSeriesChartPlot.ceiling(for: .greatestFiniteMagnitude) == .greatestFiniteMagnitude)
    }

    @Test
    func `accessibility label names every series and reference`() throws {
        let chart = try Chart(
            kind: .bars,
            title: "Tokens",
            unit: "k",
            points: [],
            series: [
                Chart.Series(name: "Input", stack: "t", points: [Chart.Point(label: "Mon", value: 1)]),
                Chart.Series(name: "Output", stack: "t", points: [Chart.Point(label: "Mon", value: 2)]),
            ],
            references: [Chart.Reference(value: 4, label: "Cap")])

        #expect(ProviderDetailSeriesChartPlot.accessibilityLabel(for: chart)
            == "Tokens: Input: Mon 1.0 k; Output: Mon 2.0 k; Cap 4.0 k")
    }

    @Test
    func `privacy redaction keeps series stacks and references`() throws {
        let chart = try Chart(
            kind: .bars,
            points: [],
            series: [
                Chart.Series(name: "Pool user@example.com", stack: "t", points: [Chart.Point(label: "Mon", value: 1)]),
                Chart.Series(name: "Output", stack: "t", points: [Chart.Point(label: "Mon", value: 2)]),
            ],
            references: [Chart.Reference(value: 4, label: "Cap", style: .solid)])
        let model = try UsageMenuCardView.Model.make(Self.input(
            details: [ProviderDetailSection(rows: [], chart: chart)],
            hidePersonalInfo: true))
        let redacted = try #require(model.providerDetails.first?.chart)

        #expect(redacted.series.map(\.name) == ["Pool", "Output"])
        #expect(redacted.series.map(\.stack) == ["t", "t"])
        #expect(redacted.references == chart.references)
    }

    @Test
    func `height fingerprint tracks the series count`() throws {
        let two = try UsageMenuCardView.Model.make(Self.input(details: [
            ProviderDetailSection(rows: [], chart: Self.seriesChart(names: ["A", "B"], kind: .bars)),
        ]))
        let three = try UsageMenuCardView.Model.make(Self.input(details: [
            ProviderDetailSection(rows: [], chart: Self.seriesChart(names: ["A", "B", "C"], kind: .bars)),
        ]))

        #expect(two.heightFingerprint(section: "card") != three.heightFingerprint(section: "card"))
    }

    // MARK: - Fixtures

    private static func seriesChart(names: [String], kind: Chart.Kind) throws -> Chart {
        try Chart(kind: kind, title: "Daily", points: [], series: names.enumerated().map { index, name in
            try Chart.Series(name: name, stack: "s", points: [Chart.Point(label: "Mon", value: Double(index + 1))])
        })
    }

    private static func height(of chart: Chart) throws -> CGFloat {
        let section = try ProviderDetailSection(rows: [], chart: chart)
        let view = ProviderDetailSectionsContent(sections: [section], chartColor: .blue)
        return NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude))
            .height
    }

    private static func input(
        details: [ProviderDetailSection],
        hidePersonalInfo: Bool = false) -> UsageMenuCardView.Model.Input
    {
        let provider: UsageProvider = .synthetic
        return UsageMenuCardView.Model.Input(
            provider: provider,
            metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
            snapshot: UsageSnapshot(
                primary: nil,
                secondary: nil,
                details: details,
                updatedAt: Date()),
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: hidePersonalInfo,
            paceVisible: true,
            now: Date())
    }
}
