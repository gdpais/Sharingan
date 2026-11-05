import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLICostLocalProjectsTests {
    @Test(arguments: [UsageProvider.claude, .codex])
    func `cost JSON lists projects for providers with local projects`(provider: UsageProvider) throws {
        let payload = CodexBarCLI.makeCostPayload(provider: provider, snapshot: self.snapshot(), error: nil)

        #expect(payload.projects.map(\.name) == ["client-a"])
        #expect(payload.projects.first?.path == "/work/client-a")
        let json = try #require(CodexBarCLI.encodeJSON(payload, pretty: false))
        #expect(json.contains("\"name\":\"client-a\""))
        // The Core history carried for dashboard insights never reaches cost JSON.
        #expect(!json.contains("insightSource"))
        #expect(!json.contains("hourly"))
    }

    @Test
    func `cost JSON omits projects for providers without local projects`() {
        #expect(!UsageProvider.cursor.supportsLocalProjects)
        let payload = CodexBarCLI.makeCostPayload(provider: .cursor, snapshot: self.snapshot(), error: nil)

        #expect(payload.projects.isEmpty)
        #expect(payload.insightSource?.projects.isEmpty == true)
    }

    @Test
    func `cost JSON keeps its top level keys`() throws {
        let payload = CodexBarCLI.makeCostPayload(provider: .claude, snapshot: self.snapshot(), error: nil)
        let json = try #require(CodexBarCLI.encodeJSON(payload, pretty: false))
        let data = try #require(json.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == [
            "provider", "source", "updatedAt", "currencyCode", "historyDays", "reportingPeriod", "historyLabel",
            "historyCoverageIsEstablished", "last30DaysTokens", "last30DaysCostUSD", "daily", "projects", "totals",
            "provenance", "coverage",
        ])
    }

    private func snapshot() -> CostUsageTokenSnapshot {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-04-02",
            inputTokens: 30,
            outputTokens: 10,
            totalTokens: 40,
            costUSD: 0.04,
            modelsUsed: ["claude-sonnet-4"],
            modelBreakdowns: [
                CostUsageDailyReport.ModelBreakdown(modelName: "claude-sonnet-4", costUSD: 0.04, totalTokens: 40),
            ])
        return CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 40,
            last30DaysCostUSD: 0.04,
            daily: [entry],
            projects: [
                CostUsageProjectBreakdown(
                    name: "client-a",
                    path: "/work/client-a",
                    totalTokens: 40,
                    totalCostUSD: 0.04,
                    daily: [entry],
                    modelBreakdowns: nil),
            ],
            hourly: [
                CostUsageHourlyEntry(hour: Date(timeIntervalSince1970: 1_775_088_000), totalTokens: 40, costUSD: 0.04),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_775_131_200))
    }
}
