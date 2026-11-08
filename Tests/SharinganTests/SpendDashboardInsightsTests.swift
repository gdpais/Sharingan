import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

struct SpendDashboardInsightsTests {
    @Test
    func `model share comes from the daily model breakdowns`() throws {
        let input = Self.input(daily: [
            Self.entry(day: "2026-07-14", models: [("fixture-large", 3), ("fixture-small", 1)]),
            Self.entry(day: "2026-07-15", models: [("fixture-large", 1), ("fixture-small", 1), ("  ", 5)]),
        ])

        let group = try Self.group(inputs: [input])
        let share = try #require(group.insights.modelShare)

        #expect(share.bucket == .day)
        #expect(share.series.map(\.id) == ["codex:fixture-large", "codex:fixture-small"])
        #expect(share.series.map(\.total) == [4, 2])
        #expect(share.points.map(\.share) == [0.75, 0.25, 0.5, 0.5])
        #expect(group.insights.modelNames == [
            "codex:fixture-large": "fixture-large",
            "codex:fixture-small": "fixture-small",
        ])
    }

    @Test
    func `a model name shared by two providers carries its provider`() throws {
        let codex = Self.input(daily: [Self.entry(day: "2026-07-15", models: [("fixture-shared", 2)])])
        let claude = Self.input(
            id: "claude",
            provider: .claude,
            displayName: "Claude",
            daily: [Self.entry(day: "2026-07-15", models: [("fixture-shared", 1)])])

        let group = try Self.group(inputs: [codex, claude])

        #expect(group.insights.modelNames["codex:fixture-shared"] == "fixture-shared · Codex")
        #expect(group.insights.modelNames["claude:fixture-shared"] == "fixture-shared · Claude")
    }

    @Test
    func `project trends follow per project daily rows and skip independent chats`() throws {
        let group = try Self.group(inputs: [Self.input(projects: Self.projects())])
        let trends = try #require(group.insights.projectTrends)

        #expect(trends.trends.map(\.id) == [Self.alphaID, Self.betaID])
        #expect(trends.trends.map(\.total) == [5, 4])
        #expect(trends.comparisonDayCount == 15)
        #expect(trends.trends.map(\.change) == [.percent(0.5), .ended])
        #expect(trends.trends.first?.points.count == 30)
        #expect(group.insights.projectIdentities[Self.alphaID]?.projectName == "alpha")
        #expect(group.insights.projectIdentities[Self.alphaID]?.providerName == "Codex")
        #expect(group.insights.projectIdentities["codex-a:path:/fixtures/chat"] == nil)
    }

    @Test
    func `menu builds skip the insight panels`() throws {
        let input = Self.input(
            daily: [Self.entry(day: "2026-07-15", models: [("fixture-large", 3), ("fixture-small", 1)])],
            projects: Self.projects())

        let menu = try Self.group(inputs: [input], includesInsightTiles: false)
        let window = try Self.group(inputs: [input])

        #expect(menu.insights == SpendDashboardInsights())
        // The rest of the group, including the Projects list, is still built for the menu.
        #expect(menu.projects.map(\.id) == ["codex-a:path:/fixtures/chat", Self.alphaID, Self.betaID])
        #expect(window.insights.modelShare != nil)
        #expect(window.insights.projectTrends != nil)
    }

    @Test
    func `a source with a shorter history has no change against the longer range`() throws {
        let recent = Self.input(
            id: "codex-b",
            historyDays: 10,
            projects: [Self.project(name: "gamma", path: "/fixtures/gamma", days: [("2026-07-15", 6)])])

        let group = try Self.group(inputs: [Self.input(projects: Self.projects()), recent])
        let trends = try #require(group.insights.projectTrends)
        let changes = Dictionary(uniqueKeysWithValues: trends.trends.map { ($0.id, $0.change) })

        // Gamma's source began scanning inside the earlier half, so "New" would be a guess.
        #expect(trends.comparisonDayCount == 15)
        #expect(changes["codex-b:path:/fixtures/gamma"] == .unavailable)
        #expect(changes[Self.alphaID] == .percent(0.5))
    }

    @Test
    func `trend labels redact with the projects list numbering`() throws {
        try SharinganLocalizationOverride.$appLanguage.withValue("en") {
            let group = try Self.group(inputs: [Self.input(projects: Self.projects())])
            let trends = try #require(group.insights.projectTrends)
            let rows = spendInsightsProjectTrendRows(
                trends: trends.trends,
                identities: group.insights.projectIdentities,
                listRows: spendDashboardProjectRows(group.projects, isProjectless: false))

            let alpha = try #require(rows[Self.alphaID])
            #expect(alpha.displayIdentity(hidePersonalInfo: true).name == "Project 1")
            #expect(alpha.displayIdentity(hidePersonalInfo: true).path == nil)
            #expect(alpha.displayIdentity(hidePersonalInfo: false).name == "alpha")
            #expect(rows[Self.betaID]?.displayIdentity(hidePersonalInfo: true).name == "Project 2")
        }
    }

    @Test
    func `projects missing from a selected day list continue its numbering`() throws {
        try SharinganLocalizationOverride.$appLanguage.withValue("en") {
            let group = try Self.group(inputs: [Self.input(projects: Self.projects())], selectedDay: Self.lastDay)
            let trends = try #require(group.insights.projectTrends)
            let listRows = spendDashboardProjectRows(group.projects, isProjectless: false)
            let rows = spendInsightsProjectTrendRows(
                trends: trends.trends,
                identities: group.insights.projectIdentities,
                listRows: listRows)

            // The selected day only lists alpha; the trends still cover the whole range.
            #expect(listRows.map(\.id) == [Self.alphaID])
            #expect(trends.trends.map(\.id) == [Self.alphaID, Self.betaID])
            #expect(rows[Self.alphaID]?.displayIdentity(hidePersonalInfo: true).name == "Project 1")
            #expect(rows[Self.betaID]?.displayIdentity(hidePersonalInfo: true).name == "Project 2")
        }
    }

    @Test
    func `model share slots follow the share ranking with other in the neutral slot`() {
        let observations = ["a", "b", "c", "d", "e", "f", "g"].enumerated().map { index, id in
            SpendShareOverTime.Observation(day: Self.now, seriesID: id, value: Double(10 - index))
        }
        let share = SpendShareOverTime(observations: observations, topCount: 5, bucket: .day, calendar: Self.calendar)

        let slots = spendInsightsModelShareSlots(share)

        #expect(slots["a"] == .index(0))
        #expect(slots["e"] == .index(4))
        #expect(slots[SpendShareOverTime.otherSeriesID] == .other)
        #expect(slots["f"] == nil)
    }

    @Test
    func `change text is signed and names new and missing values`() {
        SharinganLocalizationOverride.$appLanguage.withValue("en") {
            #expect(spendInsightsChangeText(.percent(0.5)) == "+50%")
            #expect(spendInsightsChangeText(.percent(-0.25)) == "-25%")
            #expect(spendInsightsChangeText(.ended) == "-100%")
            #expect(spendInsightsChangeText(.unchanged) == "0%")
            #expect(spendInsightsChangeText(.new) == "New")
            #expect(spendInsightsChangeText(.unavailable) == "—")
        }
    }

    @Test
    func `domain widens to whole buckets`() {
        let start = Self.now.addingTimeInterval(-9 * 86400) // Tuesday 2026-07-07
        let domain = spendInsightsDomain(start...Self.now, bucket: .week, calendar: Self.calendar)

        #expect(domain.lowerBound == Self.now.addingTimeInterval(-10 * 86400))
        #expect(domain.upperBound == Self.now.addingTimeInterval(4 * 86400))
    }

    // MARK: - Fixtures

    private static let now = Date(timeIntervalSince1970: 1_784_160_000) // Thursday 2026-07-16 00:00:00 UTC
    private static let lastDay = Date(timeIntervalSince1970: 1_784_073_600) // 2026-07-15 00:00:00 UTC
    private static let alphaID = "codex-a:path:/fixtures/alpha"
    private static let betaID = "codex-a:path:/fixtures/beta"

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    /// Alpha spends 2 early and 3 late in the 30-day range, beta 4 early only, and a chat spends 9 late.
    private static func projects() -> [CostUsageProjectBreakdown] {
        [
            self.project(name: "alpha", path: "/fixtures/alpha", days: [("2026-06-20", 2), ("2026-07-15", 3)]),
            self.project(name: "beta", path: "/fixtures/beta", days: [("2026-06-25", 4)]),
            self.project(name: "Planning", path: "/fixtures/chat", days: [("2026-07-15", 9)], isProjectless: true),
        ]
    }

    private static func project(
        name: String,
        path: String,
        days: [(String, Double)],
        isProjectless: Bool = false) -> CostUsageProjectBreakdown
    {
        CostUsageProjectBreakdown(
            name: name,
            path: path,
            totalTokens: nil,
            totalCostUSD: days.map(\.1).reduce(0, +),
            daily: days.map { day, cost in self.entry(day: day, cost: cost) },
            modelBreakdowns: nil,
            isProjectless: isProjectless)
    }

    private static func entry(day: String, cost: Double) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 10,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }

    private static func entry(day: String, models: [(String, Double)]) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: 10 * models.count,
            costUSD: models.map(\.1).reduce(0, +),
            modelsUsed: models.map(\.0),
            modelBreakdowns: models.map { name, cost in
                CostUsageDailyReport.ModelBreakdown(modelName: name, costUSD: cost, totalTokens: 10)
            })
    }

    private static func input(
        id: String = "codex-a",
        provider: UsageProvider = .codex,
        displayName: String = "Codex",
        historyDays: Int = 30,
        daily: [CostUsageDailyReport.Entry] = [],
        projects: [CostUsageProjectBreakdown] = []) -> SpendDashboardModel.ProviderInput
    {
        SpendDashboardModel.ProviderInput(
            id: id,
            provider: provider,
            displayName: displayName,
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: nil,
                last30DaysCostUSD: nil,
                historyDays: historyDays,
                daily: daily.isEmpty ? [self.entry(day: "2026-07-15", cost: 10)] : daily,
                projects: projects,
                updatedAt: self.now))
    }

    private static func group(
        inputs: [SpendDashboardModel.ProviderInput],
        selectedDay: Date? = nil,
        includesInsightTiles: Bool = true) throws -> SpendDashboardModel.CurrencyGroup
    {
        let model = SpendDashboardModel.build(
            inputs: inputs,
            requestedDays: 30,
            now: self.now,
            calendar: self.calendar,
            selectedDay: selectedDay,
            includesInsightTiles: includesInsightTiles)
        return try #require(model.groups.first)
    }
}
