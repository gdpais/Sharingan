import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct DashboardInsightsBuilderTests {
    private static let generatedAt = Date(timeIntervalSince1970: 1_793_880_000) // 2026-11-05T12:00:00Z

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    @Test
    func `insights fold claude and codex history into every section`() throws {
        let insights = try #require(self.insights(identityMode: .full))

        #expect(insights.currencyCode == "USD")
        #expect(insights.timeZone == "UTC")
        #expect(insights.range.start == "2026-10-07")
        #expect(insights.range.end == "2026-11-05")
        #expect(insights.range.days == 30)
        #expect(insights.bucket == "day")

        let costByModel = try #require(insights.costByModel)
        #expect(costByModel.map(\.provider) == ["claude", "codex"])
        let claude = try #require(costByModel.first)
        #expect(claude.models == ["claude-opus-4", "claude-sonnet-4"])
        #expect(claude.hasOther)
        #expect(claude.days.map(\.date) == ["2026-11-03", "2026-11-04", "2026-11-05"])
        let busyDay = claude.days[1]
        #expect(busyDay.total == 3)
        #expect(busyDay.segments.map(\.rank) == [0, 1])
        #expect(busyDay.segments.map(\.value) == [2, 1])
        let otherDay = claude.days[0]
        #expect(otherDay.segments.last?.isOther == true)
        #expect(otherDay.segments.last?.rank == nil)
        #expect(costByModel[1].models == ["gpt-5"])
        #expect(!costByModel[1].hasOther)
    }

    @Test
    func `tiles use the core insight tiles and omit plan value without a plan price`() throws {
        let tiles = try #require(self.insights(identityMode: .full)?.tiles)

        #expect(tiles.apiEquivalentCost == 8)
        #expect(tiles.planValue == nil)
        // Claude reports disjoint classes and Codex counts cache reads inside input.
        let cacheHitRate = try #require(tiles.cacheHitRate)
        #expect(abs(cacheHitRate.value - 4700.0 / 6800.0) < 1e-9)
        // The partly unpriced day keeps its spend but stays out of cost per 1M tokens.
        let costPerMillion = try #require(tiles.costPerMillionTokens)
        #expect(abs(costPerMillion.value - 6.0 * 1_000_000 / 7300.0) < 1e-6)
        let topModel = try #require(tiles.topModelShare)
        #expect(topModel.modelName == "claude-opus-4")
        #expect(topModel.provider == "claude")
        #expect(abs(topModel.value - 4.0 / 8.0) < 1e-9)
        // A 30-day history cannot cover the previous 30 days, so no tile has a comparison.
        #expect(cacheHitRate.previousValue == nil)
        #expect(cacheHitRate.trend.count == tiles.trendBucketCount)

        let priced = try #require(self.insights(identityMode: .full, planMonthlyPrice: 20)?.tiles?.planValue)
        #expect(abs(priced.value - 8.0 / 20.0) < 1e-9)
    }

    @Test
    func `heatmap and model share span sources on the host calendar`() throws {
        let insights = try #require(self.insights(identityMode: .full))

        let heatmap = try #require(insights.heatmap)
        #expect(heatmap.weekdays == [2, 3, 4, 5, 6, 7, 1])
        #expect(heatmap.totalCost == 6) // hourly buckets: Claude 3 + 1, Codex 2
        #expect(heatmap.busiest?.weekday == 4) // Wednesday
        #expect(heatmap.busiest?.hour == 14)
        #expect(heatmap.busiest?.level == 4)
        #expect(heatmap.cells.count == 3)
        #expect(heatmap.cells.allSatisfy { $0.cost > 0 && (1...4).contains($0.level) })

        let share = try #require(insights.modelShare)
        #expect(share.bucket == "day")
        #expect(share.series.map(\.id) == ["claude:claude-opus-4", "codex:gpt-5", "claude:claude-sonnet-4"])
        #expect(share.series.allSatisfy { !$0.isOther })
        #expect(share.series.map(\.provider) == ["claude", "codex", "claude"])
        let firstDay = share.points.filter { $0.date == "2026-11-04" }
        #expect(firstDay.map(\.series) == ["claude:claude-opus-4", "claude:claude-sonnet-4"])
        #expect(abs((firstDay.last?.shareEnd ?? 0) - 1) < 1e-9)
    }

    @Test
    func `project trends show names and paths only with full identity`() throws {
        let full = try #require(self.insights(identityMode: .full)?.projectTrends)
        let project = try #require(full.projects.first)
        #expect(full.projects.count == 1) // the independent chat is not a project
        #expect(project.label == "secret-project")
        #expect(project.path == "/Users/fixture/secret-project")
        #expect(project.provider == "claude")
        #expect(project.total == 3)
        #expect(project.change == "new")
        #expect(full.comparisonDays == 15)
        #expect(full.start == "2026-10-07")

        for mode in [DashboardIdentityMode.redacted, .none] {
            let insights = try #require(self.insights(identityMode: mode))
            #expect(insights.timeZone == nil)
            let redacted = try #require(insights.projectTrends?.projects.first)
            #expect(redacted.label == "Project 1")
            #expect(redacted.path == nil)
            let json = try #require(CodexBarCLI.encodeJSON(insights, pretty: false))
            #expect(!json.contains("secret-project"))
            #expect(!json.contains("/Users/fixture"))
        }
    }

    @Test
    func `snapshot omits insights without cost history and keeps existing keys`() throws {
        let config = CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)])
        let empty = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [],
            costPayloads: [],
            config: config,
            identityMode: .full,
            generatedAt: Self.generatedAt,
            refreshInterval: 60,
            codexBarVersion: nil)
        let emptyObject = try self.jsonObject(empty)
        #expect(Set(emptyObject.keys) == ["schemaVersion", "generatedAt", "staleAfterSeconds", "host", "providers"])

        // A cost row without Core history (an imported or failed payload) never produces insights.
        let bare = CostPayload(
            provider: "claude",
            source: "local",
            updatedAt: Self.generatedAt,
            sessionTokens: nil,
            sessionCostUSD: nil,
            historyDays: 30,
            last30DaysTokens: nil,
            last30DaysCostUSD: 3,
            daily: [],
            totals: nil,
            error: nil)
        #expect(DashboardInsightsBuilder.makeInsights(
            costPayloads: [bare],
            identityMode: .full,
            generatedAt: Self.generatedAt) == nil)
    }

    @Test
    func `snapshot adds insights beside unchanged provider rows`() throws {
        let calendar = DashboardInsightsBuilder.defaultCalendar()
        let config = CodexBarConfig(providers: [ProviderConfig(id: .claude, enabled: true)])
        let cost = CodexBarCLI.makeCostPayload(
            provider: .claude,
            snapshot: self.claudeSnapshot(calendar: calendar),
            error: nil,
            calendar: calendar)
        let snapshot = DashboardSnapshotBuilder.makeSnapshot(
            usagePayloads: [],
            costPayloads: [cost],
            config: config,
            identityMode: .redacted,
            generatedAt: Self.generatedAt,
            refreshInterval: 60,
            codexBarVersion: nil)
        let object = try self.jsonObject(snapshot)
        #expect(Set(object.keys) == [
            "schemaVersion", "generatedAt", "staleAfterSeconds", "host", "providers", "insights",
        ])
        let insights = try #require(object["insights"] as? [String: Any])
        #expect(Set(insights.keys) == [
            "currencyCode", "range", "bucket", "costByModel", "tiles", "heatmap", "modelShare", "projectTrends",
        ])
        let json = try #require(CodexBarCLI.encodeJSON(snapshot, pretty: false))
        #expect(!json.contains("secret-project"))
        #expect(!json.contains("insightSource"))
    }

    // MARK: - Fixtures

    private func insights(
        identityMode: DashboardIdentityMode,
        planMonthlyPrice: Double? = nil) -> DashboardInsightsPayload?
    {
        let calendar = Self.utc
        let payloads = [
            CodexBarCLI.makeCostPayload(
                provider: .claude,
                snapshot: self.claudeSnapshot(calendar: calendar),
                error: nil,
                calendar: calendar),
            CodexBarCLI.makeCostPayload(
                provider: .codex,
                snapshot: self.codexSnapshot(calendar: calendar),
                error: nil,
                calendar: calendar),
        ]
        return DashboardInsightsBuilder.makeInsights(
            costPayloads: payloads,
            identityMode: identityMode,
            generatedAt: Self.generatedAt,
            calendar: calendar,
            planMonthlyPrice: planMonthlyPrice)
    }

    private func day(_ offset: Int, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: Self.generatedAt)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func key(_ offset: Int, calendar: Calendar) -> String {
        DashboardInsightsBuilder.dayKey(self.day(offset, calendar: calendar), calendar: calendar)
    }

    private func hour(_ hour: Int, dayOffset: Int, calendar: Calendar) -> Date {
        self.day(dayOffset, calendar: calendar).addingTimeInterval(TimeInterval(hour * 3600))
    }

    /// Three Claude days: one with an unattributed remainder and unpriced tokens, then two fully priced days.
    private func claudeSnapshot(calendar: Calendar) -> CostUsageTokenSnapshot {
        let busy = CostUsageDailyReport.Entry(
            date: self.key(-1, calendar: calendar),
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
            last30DaysTokens: 7300,
            last30DaysCostUSD: 6,
            historyDays: 30,
            daily: [
                CostUsageDailyReport.Entry(
                    date: self.key(-2, calendar: calendar),
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: 1000,
                    costUSD: 2,
                    modelsUsed: ["claude-opus-4"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(modelName: "claude-opus-4", costUSD: 1, totalTokens: 500),
                        CostUsageDailyReport.ModelBreakdown(
                            modelName: "fictional-unpriced",
                            costUSD: nil,
                            totalTokens: 500),
                    ]),
                busy,
                CostUsageDailyReport.Entry(
                    date: self.key(0, calendar: calendar),
                    inputTokens: 500,
                    outputTokens: 100,
                    cacheReadTokens: 1500,
                    totalTokens: 2100,
                    costUSD: 1,
                    modelsUsed: ["claude-opus-4"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(modelName: "claude-opus-4", costUSD: 1, totalTokens: 2100),
                    ]),
            ],
            projects: [
                CostUsageProjectBreakdown(
                    name: "secret-project",
                    path: "/Users/fixture/secret-project",
                    totalTokens: 4200,
                    totalCostUSD: 3,
                    daily: [busy],
                    modelBreakdowns: nil),
                CostUsageProjectBreakdown(
                    name: "Independent chat",
                    path: nil,
                    totalTokens: 2100,
                    totalCostUSD: 1,
                    daily: [busy],
                    modelBreakdowns: nil,
                    isProjectless: true),
            ],
            hourly: [
                CostUsageHourlyEntry(
                    hour: self.hour(14, dayOffset: -1, calendar: calendar),
                    totalTokens: 4200,
                    costUSD: 3),
                CostUsageHourlyEntry(
                    hour: self.hour(9, dayOffset: 0, calendar: calendar),
                    totalTokens: 2100,
                    costUSD: 1),
            ],
            updatedAt: Self.generatedAt)
    }

    private func codexSnapshot(calendar: Calendar) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 1000,
            last30DaysCostUSD: 2,
            historyDays: 30,
            daily: [
                CostUsageDailyReport.Entry(
                    date: self.key(0, calendar: calendar),
                    inputTokens: 800,
                    outputTokens: 200,
                    cacheReadTokens: 200,
                    totalTokens: 1000,
                    costUSD: 2,
                    modelsUsed: ["gpt-5"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(modelName: "gpt-5", costUSD: 2, totalTokens: 1000),
                    ]),
            ],
            hourly: [
                CostUsageHourlyEntry(
                    hour: self.hour(10, dayOffset: 0, calendar: calendar),
                    totalTokens: 1000,
                    costUSD: 2),
            ],
            updatedAt: Self.generatedAt)
    }

    private func jsonObject(_ payload: some Encodable) throws -> [String: Any] {
        let json = try #require(CodexBarCLI.encodeJSON(payload, pretty: false))
        let data = try #require(json.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
