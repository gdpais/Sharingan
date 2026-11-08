import Foundation
import SharinganCore
import Testing
@testable import Sharingan

@MainActor
struct CostHistoryClaudeProjectsTests {
    @Test
    func `Claude cost history renders project rows like Codex`() {
        let snapshot = Self.snapshot(projects: [
            Self.project(name: "private-repo", path: "/Users/example/private-repo", cost: 2, tokens: 200),
            Self.project(name: "other-repo", path: "/Users/example/other-repo", cost: 1, tokens: 100),
        ])

        let claude = CostHistoryChartMenuView.renderFingerprint(from: snapshot, provider: .claude)
        let codex = CostHistoryChartMenuView.renderFingerprint(from: snapshot, provider: .codex)

        #expect(claude.projects.map(\.name) == ["private-repo", "other-repo"])
        #expect(claude.projects.map(\.path) == ["/Users/example/private-repo", "/Users/example/other-repo"])
        #expect(claude.projects == codex.projects)
        // Sessions remain Codex-only; Claude publishes project rows without a session list.
        #expect(claude.sessions.isEmpty)
    }

    @Test
    func `hidden personal info redacts Claude project names and paths in the cost menu`() {
        let snapshot = Self.snapshot(projects: [
            Self.project(name: "private-repo", path: "/Users/example/private-repo", cost: 2, tokens: 200),
        ])

        let visible = CostHistoryChartMenuView.renderFingerprint(from: snapshot, provider: .claude)
        let hidden = CostHistoryChartMenuView.renderFingerprint(
            from: snapshot, provider: .claude, hidePersonalInfo: true)

        #expect(hidden.projects.map(\.name) == [L("Project %d", 1)])
        #expect(hidden.projects.map(\.path) == [nil])
        #expect(hidden.projects.map(\.totalTokens) == visible.projects.map(\.totalTokens))
        #expect(hidden.projects.map(\.totalCostBitPattern) == visible.projects.map(\.totalCostBitPattern))
    }

    @Test
    func `Usage and Spend keeps Claude projects on Claude rows and redacts them`() throws {
        let model = SpendDashboardModel.build(
            inputs: [
                SpendDashboardModel.ProviderInput(
                    id: "claude",
                    provider: .claude,
                    displayName: "Claude",
                    snapshot: Self.snapshot(projects: [
                        Self.project(name: "claude-repo", path: "/Users/example/claude-repo", cost: 2, tokens: 200),
                    ])),
                SpendDashboardModel.ProviderInput(
                    id: "codex",
                    provider: .codex,
                    displayName: "Codex",
                    snapshot: Self.snapshot(projects: [
                        Self.project(name: "codex-repo", path: "/Users/example/codex-repo", cost: 1, tokens: 100),
                    ])),
            ],
            requestedDays: 30,
            now: Self.now,
            calendar: Self.calendar)

        let group = try #require(model.groups.first)
        let claudeRow = try #require(group.projects.first { $0.projectName == "claude-repo" })
        let codexRow = try #require(group.projects.first { $0.projectName == "codex-repo" })
        #expect(claudeRow.provider == .claude)
        #expect(claudeRow.sourceID == "claude")
        #expect(claudeRow.totalCost == 2)
        #expect(codexRow.provider == .codex)
        #expect(!group.projects.contains(where: { $0.provider == .claude && $0.projectName == "codex-repo" }))
        let hidden = claudeRow.displayIdentity(hidePersonalInfo: true)
        #expect(hidden.name == L("Project %d", claudeRow.rank))
        #expect(hidden.path == nil)
    }

    // MARK: - Fixtures

    private static let day = "2026-07-15"
    private static let now = Date(timeIntervalSince1970: 1_784_179_200) // 2026-07-16 00:00:00 UTC
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func entry(cost: Double, tokens: Int) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: self.day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }

    private static func project(name: String, path: String, cost: Double, tokens: Int) -> CostUsageProjectBreakdown {
        CostUsageProjectBreakdown(
            name: name,
            path: path,
            totalTokens: tokens,
            totalCostUSD: cost,
            daily: [self.entry(cost: cost, tokens: tokens)],
            modelBreakdowns: nil,
            sources: [
                CostUsageProjectSourceBreakdown(
                    name: name,
                    path: path,
                    totalTokens: tokens,
                    totalCostUSD: cost,
                    daily: [self.entry(cost: cost, tokens: tokens)],
                    modelBreakdowns: nil),
            ])
    }

    private static func snapshot(projects: [CostUsageProjectBreakdown]) -> CostUsageTokenSnapshot {
        let cost = projects.compactMap(\.totalCostUSD).reduce(0, +)
        let tokens = projects.compactMap(\.totalTokens).reduce(0, +)
        return CostUsageTokenSnapshot(
            sessionTokens: tokens,
            sessionCostUSD: cost,
            last30DaysTokens: tokens,
            last30DaysCostUSD: cost,
            currencyCode: "USD",
            historyDays: 30,
            daily: [self.entry(cost: cost, tokens: tokens)],
            projects: projects,
            updatedAt: self.now)
    }
}
