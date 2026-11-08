import Foundation
import SharinganCore
import Testing
@testable import SharinganCLI

struct DashboardInsightsLinuxTests {
    private static let generatedAt = Date(timeIntervalSince1970: 1_793_880_000)

    @Test
    func `producer snapshot carries insights and redacts project identity`() async throws {
        let cost = SharinganCLI.makeCostPayload(
            provider: .claude,
            snapshot: Self.snapshot(calendar: DashboardInsightsBuilder.defaultCalendar()),
            error: nil,
            calendar: DashboardInsightsBuilder.defaultCalendar())
        let producer = DashboardSnapshotProducer(
            collectUsage: { _ in UsageCommandOutput() },
            collectCost: { _, _ in [cost] },
            now: { Self.generatedAt })
        let config = SharinganConfig(providers: [ProviderConfig(id: .claude, enabled: true)])

        let redacted = try await producer.collect(
            config: config,
            refreshInterval: 0,
            sharinganVersion: nil,
            identityMode: .redacted)
        let insights = try #require(redacted.payload.insights)
        #expect(insights.currencyCode == "USD")
        #expect(insights.timeZone == nil)
        #expect(insights.costByModel?.first?.models == ["claude-opus-4", "claude-sonnet-4"])
        #expect(insights.tiles?.cacheHitRate != nil)
        #expect(insights.tiles?.planValue == nil)
        #expect(insights.heatmap?.busiest?.hour == 14)
        #expect(insights.modelShare?.series.count == 2)
        #expect(insights.projectTrends?.projects.first?.label == "Project 1")
        #expect(insights.projectTrends?.projects.first?.path == nil)
        let json = try #require(String(data: JSONEncoder().encode(redacted.payload), encoding: .utf8))
        #expect(json.contains("\"insights\""))
        #expect(!json.contains("linux-secret-project"))

        let full = try await producer.collect(
            config: config,
            refreshInterval: 0,
            sharinganVersion: nil,
            identityMode: .full)
        #expect(full.payload.insights?.projectTrends?.projects.first?.label == "linux-secret-project")
        #expect(full.payload.insights?.projectTrends?.projects.first?.path == "/home/fixture/linux-secret-project")
    }

    @Test
    func `snapshot without cost history has no insights key`() async throws {
        let producer = DashboardSnapshotProducer(
            collectUsage: { _ in UsageCommandOutput() },
            collectCost: { _, _ in [] },
            now: { Self.generatedAt })
        let result = try await producer.collect(
            config: SharinganConfig(providers: [ProviderConfig(id: .claude, enabled: true)]),
            refreshInterval: 0,
            sharinganVersion: nil)
        #expect(result.payload.insights == nil)
        let json = try #require(String(data: JSONEncoder().encode(result.payload), encoding: .utf8))
        #expect(!json.contains("insights"))
    }

    @Test
    func `day keys parse strictly on the host calendar`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day = DashboardInsightsBuilder.day("2026-11-04", calendar: calendar)
        #expect(day.map { DashboardInsightsBuilder.dayKey($0, calendar: calendar) } == "2026-11-04")
        #expect(DashboardInsightsBuilder.day("2026-11-04T10:00:00Z", calendar: calendar) == day)
        #expect(DashboardInsightsBuilder.day("2026-02-30", calendar: calendar) == nil)
        #expect(DashboardInsightsBuilder.day("2026-1-04", calendar: calendar) == nil)
        #expect(DashboardInsightsBuilder.day("+026-11-04", calendar: calendar) == nil)
    }

    private static func snapshot(calendar: Calendar) -> CostUsageTokenSnapshot {
        let today = calendar.startOfDay(for: self.generatedAt)
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
        return CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 4200,
            last30DaysCostUSD: 3,
            daily: [entry],
            projects: [
                CostUsageProjectBreakdown(
                    name: "linux-secret-project",
                    path: "/home/fixture/linux-secret-project",
                    totalTokens: 4200,
                    totalCostUSD: 3,
                    daily: [entry],
                    modelBreakdowns: nil),
            ],
            hourly: [
                CostUsageHourlyEntry(hour: yesterday.addingTimeInterval(14 * 3600), totalTokens: 4200, costUSD: 3),
            ],
            updatedAt: self.generatedAt)
    }
}
