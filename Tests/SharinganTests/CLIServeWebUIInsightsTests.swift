import Foundation
import JavaScriptCore
import SharinganCore
import Testing
@testable import SharinganCLI

struct CLIServeWebUIInsightsTests {
    private var html: String {
        String(bytes: CLIServeWebUI.response().body, encoding: .utf8) ?? ""
    }

    @Test
    func `insight markers are replaced and the page adds no external resources`() {
        let html = self.html
        #expect(!html.contains("__INSIGHTS_STYLE__"))
        #expect(!html.contains("__INSIGHTS_SCRIPT__"))
        #expect(html.contains(#"<section id="insights" class="insights" aria-label="Insights"></section>"#))
        #expect(html.contains("function renderInsights(insights)"))
        #expect(html.contains("renderInsights(snapshot.insights);"))
        // The palette copies ChartPalette's first light and dark slots.
        #expect(html.contains("--series-0: #2A78D6;"))
        #expect(html.contains("--series-0: #3987E5;"))
        #expect(!html.contains("<script src="))
    }

    @Test
    func `snapshots without insights keep the section empty`() throws {
        let context = try self.recordingContext()
        context.evaluateScript("renderSnapshot(fixture);")
        #expect(context.exception == nil)
        #expect(context.evaluateScript("elements.insights.children.length")?.toInt32() == 0)
        #expect(context.evaluateScript(
            "recordedNodes(elements.providers).filter(x => x.tagName === 'svg').length")?.toInt32() == 1)
    }

    @Test
    func `builder insights render every section with keyboard reachable marks`() throws {
        let insights = try #require(self.builderInsightsJSON())
        let context = try self.recordingContext()
        context.evaluateScript("fixture.insights = \(insights); renderSnapshot(fixture);")
        #expect(context.exception == nil)
        let text = try #require(context.evaluateScript("recordedText(elements.insights)")?.toArray() as? [String])
        for expected in [
            "Insights", "Claude · cost by model", "Model share over time", "Spend by weekday and hour",
            "Project trends", "Cache hit rate", "Cost per 1M tokens", "Top model share", "Project 1",
        ] {
            #expect(text.contains { $0.contains(expected) }, "missing \(expected)")
        }
        #expect(!text.contains("Plan value"))
        #expect(!text.contains { $0.contains("secret-project") })
        #expect((context.evaluateScript(
            "recordedNodes(elements.insights).filter(x => x.tagName === 'svg').length")?.toInt32() ?? 0) >= 4)
        #expect((context.evaluateScript(
            "recordedNodes(elements.insights).filter(x => x.attributes.tabindex === '0').length")?
            .toInt32() ?? 0) >= 4)
        #expect(context.evaluateScript("""
        recordedNodes(elements.insights).some(x => x.tagName === 'title' && x.textContent.includes('claude-opus-4'))
        """)?.toBool() == true)
        // Provider cards render exactly as they do without insights.
        #expect(context.evaluateScript(
            "recordedNodes(elements.providers).filter(x => x.tagName === 'svg').length")?.toInt32() == 1)
    }

    @Test
    func `malformed insights never break provider cards and sign out clears them`() throws {
        let context = try self.recordingContext()
        context.evaluateScript("""
        fixture.insights = {costByModel: 'nope', tiles: 5, heatmap: {cells: 3}, projectTrends: {projects: [{}]}};
        renderSnapshot(fixture);
        """)
        #expect(context.exception == nil)
        #expect(context.evaluateScript(
            "recordedNodes(elements.providers).filter(x => x.tagName === 'svg').length")?.toInt32() == 1)
        let insights = try #require(self.builderInsightsJSON())
        context.evaluateScript("""
        fixture.insights = \(insights);
        renderSnapshot(fixture);
        elements.token.focus = () => {};
        showTokenForm();
        """)
        #expect(context.exception == nil)
        #expect(context.evaluateScript("elements.insights.children.length")?.toInt32() == 0)
    }

    @Test
    func `nice ticks follow the app's 1-2-5 scale`() throws {
        let context = try self.recordingContext()
        #expect(context.evaluateScript("JSON.stringify(niceTicks(3.9))")?.toString() == "[0,1,2,3,4]")
        #expect(context.evaluateScript("JSON.stringify(niceTicks(0.07))")?.toString() == "[0,0.02,0.04,0.06,0.08]")
        #expect(context.evaluateScript("JSON.stringify(niceTicks(1))")?.toString() == "[0,0.5,1]")
        #expect(context.evaluateScript("JSON.stringify(niceTicks(0))")?.toString() == "[]")
    }

    // MARK: - Fixtures

    private func builderInsightsJSON() -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = Date(timeIntervalSince1970: 1_793_880_000)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let entry = CostUsageDailyReport.Entry(
            date: DashboardInsightsBuilder.dayKey(yesterday, calendar: calendar),
            inputTokens: 1000,
            outputTokens: 200,
            cacheReadTokens: 3000,
            cacheCreationTokens: 0,
            totalTokens: 4200,
            costUSD: 3,
            modelsUsed: ["claude-opus-4", "claude-sonnet-4"],
            modelBreakdowns: [
                CostUsageDailyReport.ModelBreakdown(modelName: "claude-opus-4", costUSD: 2, totalTokens: 3000),
                CostUsageDailyReport.ModelBreakdown(modelName: "claude-sonnet-4", costUSD: 1, totalTokens: 1200),
            ])
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 4200,
            last30DaysCostUSD: 3,
            daily: [entry],
            projects: [CostUsageProjectBreakdown(
                name: "secret-project",
                path: "/Users/fixture/secret-project",
                totalTokens: 4200,
                totalCostUSD: 3,
                daily: [entry],
                modelBreakdowns: nil)],
            hourly: [CostUsageHourlyEntry(
                hour: yesterday.addingTimeInterval(14 * 3600),
                totalTokens: 4200,
                costUSD: 3)],
            updatedAt: now)
        let insights = DashboardInsightsBuilder.makeInsights(
            costPayloads: [SharinganCLI.makeCostPayload(
                provider: .claude,
                snapshot: snapshot,
                error: nil,
                calendar: calendar)],
            identityMode: .redacted,
            generatedAt: now,
            calendar: calendar)
        return insights.flatMap { SharinganCLI.encodeJSON($0, pretty: false) }
    }

    private func recordingContext() throws -> JSContext {
        let context = try #require(JSContext())
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("WebUI")
        let dom = try String(contentsOf: root.appendingPathComponent("recording-dom.js"), encoding: .utf8)
        context.evaluateScript(dom)
        let html = self.html
        let start = try #require(html.range(of: "<script>"))
        let end = try #require(html.range(of: "</script>"))
        context.evaluateScript(String(html[start.upperBound..<end.lowerBound]))
        let fixture = try String(
            contentsOf: root.appendingPathComponent("account-group-snapshot.json"),
            encoding: .utf8)
        context.evaluateScript("const fixture = \(fixture);")
        context.evaluateScript("""
        state.costHistories.claude = [{date:'2026-09-13',cost:3},{date:'2026-09-14',cost:2}];
        """)
        #expect(context.exception == nil)
        return context
    }
}
