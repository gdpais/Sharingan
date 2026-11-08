import Foundation
import SwiftUI
import Testing
@testable import Sharingan
@testable import SharinganCore

/// Card layout applied to menu card models, through the model seams instead of live menus.
@MainActor
struct MenuCardLayoutProjectionTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Defaults

    @Test
    func `the default layout leaves the card and its fingerprint untouched`() {
        let model = Self.model()
        let fingerprint = model.heightFingerprint(section: "card")
        #expect(model.applyingCardLayout(nil).heightFingerprint(section: "card") == fingerprint)

        var linksOnly = MenuCardLayout.default
        linksOnly.setMenuItem(.usageDashboard, visible: false)
        for layout in [MenuCardLayout.default, linksOnly] {
            let applied = model.applyingCardLayout(MenuCardLayoutContext(layout: layout))
            #expect(applied.cardLayout.resolved == nil)
            #expect(applied.cardLayout.arrangedOrder == nil)
            #expect(applied.heightFingerprint(section: "card") == fingerprint)
            #expect(applied.showsChartSwitch)
        }
    }

    // MARK: - Hidden sections

    @Test
    func `hidden sections drop their content from the model`() {
        var layout = MenuCardLayout.default
        layout.setVisible(false, for: .credits)
        layout.setVisible(false, for: .extraUsage)
        layout.setVisible(false, for: .usage)
        let applied = Self.model().applyingCardLayout(MenuCardLayoutContext(layout: layout))
        #expect(applied.creditsText == nil)
        #expect(applied.creditsProgressPercent == nil)
        #expect(applied.providerCost == nil)
        #expect(applied.metrics.isEmpty)
        #expect(applied.tokenUsage != nil)
        #expect(applied.inlineUsageDashboard?.kpis.isEmpty == false)
        // Pace stays listed: it is visible and the card reports pace, even with its rows hidden.
        #expect(applied.cardLayout.resolved?.sections == [.pace, .chart, .cost])
        // Hiding alone keeps the built-in arrangement.
        #expect(applied.cardLayout.arrangedOrder == nil)
    }

    @Test
    func `hiding cost keeps the spend chart and switches to the arranged card`() throws {
        var layout = MenuCardLayout.default
        layout.setVisible(false, for: .cost)
        let applied = Self.model().applyingCardLayout(MenuCardLayoutContext(layout: layout))
        #expect(applied.tokenUsage == nil)
        let dashboard = try #require(applied.inlineUsageDashboard)
        #expect(!dashboard.points.isEmpty)
        #expect(!dashboard.hasNonChartContent)
        #expect(applied.showsChartSwitch)
        #expect(applied.cardLayout.arrangedOrder == [.usage, .chart, .credits, .extraUsage])
        #expect(MenuCardArrangement.blocks(
            for: applied,
            order: [.usage, .chart, .credits, .extraUsage, .cost],
            includesStandaloneSections: true) == [.usage, .chart, .credits, .extraUsage])
    }

    @Test
    func `hiding pace clears pace text, markers and daily targets`() throws {
        var layout = MenuCardLayout.default
        layout.setVisible(false, for: .pace)
        let original = Self.model()
        #expect(original.cardLayoutAvailability(burndown: false, planFit: false).sections.contains(.pace))
        let applied = original.applyingCardLayout(MenuCardLayoutContext(layout: layout))
        let primary = try #require(applied.metrics.first)
        #expect(primary.pacePercent == nil)
        #expect(primary.detailLeftText == nil)
        #expect(primary.dailyTargetText == nil)
        #expect(applied.metrics.last?.detailLeftText == "Balance note")
        #expect(applied.providerCost?.dailyTargetText == nil)
        #expect(!applied.detailPaceVisible)
        #expect(applied.heightFingerprint(section: "card") != original.heightFingerprint(section: "card"))
    }

    // MARK: - Chart choice

    @Test
    func `live and spend each keep only their own chart`() {
        let live = Self.model().applyingCardLayout(MenuCardLayoutContext(layout: MenuCardLayout(chart: .live)))
        #expect(live.throughput != nil)
        #expect(live.inlineUsageDashboard?.points.isEmpty == true)
        #expect(live.inlineUsageDashboard?.kpis.isEmpty == false)
        #expect(!live.showsChartSwitch)

        let spend = Self.model().applyingCardLayout(MenuCardLayoutContext(layout: MenuCardLayout(chart: .spend)))
        #expect(spend.throughput == nil)
        #expect(spend.inlineUsageDashboard?.points.isEmpty == false)
        #expect(spend.cardLayout.resolved?.chart == .spend)

        let none = Self.model().applyingCardLayout(MenuCardLayoutContext(layout: MenuCardLayout(chart: .none)))
        #expect(none.throughput == nil)
        #expect(none.inlineUsageDashboard?.points.isEmpty == true)
        #expect(none.cardLayout.resolved?.contains(.chart) == false)
    }

    @Test
    func `a chart the provider has no data for leaves the slot empty`() {
        let liveWithoutThroughput = Self.model(throughput: false)
            .applyingCardLayout(MenuCardLayoutContext(layout: MenuCardLayout(chart: .live)))
        #expect(liveWithoutThroughput.cardLayout.resolved?.chart == MenuCardChartChoice.none)
        #expect(liveWithoutThroughput.inlineUsageDashboard?.points.isEmpty == true)

        let burndownWithoutHistory = Self.model()
            .applyingCardLayout(MenuCardLayoutContext(layout: MenuCardLayout(chart: .burndown)))
        #expect(burndownWithoutHistory.cardLayout.resolved?.chart == MenuCardChartChoice.none)
        #expect(burndownWithoutHistory.cardLayout.insightChart == nil)
        #expect(burndownWithoutHistory.throughput == nil)
    }

    @Test
    func `burn down from the provider's history takes the chart slot`() throws {
        let chart = try #require(MenuCardInsightChartBuilder.burndown(
            provider: .codex,
            histories: [Self.weeklyHistory()],
            workDays: nil,
            now: Self.now))
        #expect(chart.seriesID == "weekly:10080")
        #expect(chart.title.hasPrefix("Burn Down · "))
        let applied = Self.model(throughput: false, spendPoints: false, metrics: false, credits: false)
            .applyingCardLayout(MenuCardLayoutContext(layout: MenuCardLayout(chart: .burndown), burndown: chart))
        #expect(applied.cardLayout.resolved?.chart == .burndown)
        #expect(applied.cardLayout.insightChart != nil)
        #expect(applied.hasUsageContent)
        #expect(MenuCardArrangement.blocks(
            for: applied,
            order: [.chart],
            includesStandaloneSections: true) == [.chart])
        #expect(MenuCardBurndownChartContent.summary(model: chart.model).contains("%"))
    }

    @Test
    func `plan fit bars sit in fixed slots ending at the current window`() throws {
        let chart = try #require(MenuCardInsightChartBuilder.planFit(
            provider: .codex,
            histories: [Self.weeklyHistory()],
            snapshot: nil,
            now: Self.now))
        #expect(chart.title.hasPrefix("Plan fit · "))
        #expect(chart.slotCount == PlanFitChartLayout.minimumSlots)
        #expect(chart.bars.map(\.x) == [5, 6, 7])
        #expect(chart.bars.map(\.isCapped) == [true, false, false])
        #expect(chart.bars.last?.isCurrent == true)
        #expect(chart.summary.settledWindowCount == 2)
    }

    @Test
    func `no history means no burn down or plan fit`() {
        #expect(MenuCardInsightChartBuilder.burndown(provider: .claude, histories: [], workDays: nil, now: Self.now)
            == nil)
        #expect(MenuCardInsightChartBuilder.planFit(provider: .claude, histories: [], snapshot: nil, now: Self.now)
            == nil)
    }

    // MARK: - Order and fingerprint

    @Test
    func `a moved section draws the card section by section in the new order`() throws {
        var layout = MenuCardLayout.default
        layout.move(.cost, by: -3)
        let applied = Self.model(credits: false).applyingCardLayout(MenuCardLayoutContext(layout: layout))
        let order = try #require(applied.cardLayout.arrangedOrder)
        #expect(order == [.usage, .cost, .chart, .extraUsage])
        #expect(MenuCardArrangement.blocks(for: applied, order: order, includesStandaloneSections: true)
            == [.usage, .cost, .chart, .extraUsage])
        // A split menu's usage row leaves token cost, credits and extra usage to their own rows.
        #expect(MenuCardArrangement.blocks(for: applied, order: order, includesStandaloneSections: false)
            == [.usage, .cost, .chart])
        #expect(!MenuCardArrangement.dividesSections(.usage, .chart))
        #expect(!MenuCardArrangement.dividesSections(.chart, .usage))
        #expect(MenuCardArrangement.dividesSections(.usage, .cost))
        #expect(MenuCardArrangement.dividesSections(.cost, .chart))
    }

    @Test
    func `the height fingerprint changes with order and chart choice`() {
        let model = Self.model()
        let standard = model.heightFingerprint(section: "card")
        var moved = MenuCardLayout.default
        moved.move(.credits, by: -1)
        let reordered = model.applyingCardLayout(MenuCardLayoutContext(layout: moved))
            .heightFingerprint(section: "card")
        var movedBack = moved
        movedBack.move(.credits, by: 1)
        movedBack.chart = .spend
        let spend = model.applyingCardLayout(MenuCardLayoutContext(layout: movedBack))
            .heightFingerprint(section: "card")
        #expect(reordered != standard)
        #expect(spend != standard)
        #expect(spend != reordered)
    }

    @Test
    func `usage rows keep today's note rules when a cost summary is present`() {
        var model = Self.model()
        model.usageNotes = ["General note", "Renews May 1"]
        model.subscriptionNotes = ["Renews May 1"]
        let rows = MenuCardArrangement.usageRowsModel(model)
        #expect(rows.inlineUsageDashboard == nil)
        #expect(rows.throughput == nil)
        #expect(rows.cardLayout.resolved == nil)
        // Codex keeps plan notes beside the quota rows, so nothing else is repeated below them.
        #expect(rows.supplementalUsageNotes.isEmpty)
        #expect(rows.quotaSubscriptionNotes == ["Renews May 1"])
    }

    // MARK: - Fixtures

    private static func model(
        throughput: Bool = true,
        spendPoints: Bool = true,
        metrics: Bool = true,
        credits: Bool = true) -> UsageMenuCardView.Model
    {
        UsageMenuCardView.Model(
            provider: .codex,
            providerName: "Codex",
            email: "",
            subtitleText: "Updated just now",
            subtitleStyle: .info,
            planText: nil,
            metrics: metrics ? [self.paceMetric(), self.balanceMetric()] : [],
            usageNotes: [],
            throughput: throughput ? ProviderThroughputSection(snapshot: self.throughputSnapshot()) : nil,
            openAIAPIUsage: nil,
            inlineUsageDashboard: self.dashboard(points: spendPoints),
            creditsText: credits ? "12 credits" : nil,
            creditsProgressPercent: credits ? 40 : nil,
            providerCost: .init(
                title: "Extra usage",
                percentUsed: 20,
                spendLine: "$2 / $10",
                percentLine: nil,
                dailyTargetText: "≈ $1 / day"),
            tokenUsage: .init(
                sessionLine: "Today: $1",
                monthLine: "30 days: $9",
                hintLine: nil,
                errorLine: nil,
                errorCopyText: nil),
            placeholder: nil,
            progressColor: .blue)
    }

    private static func paceMetric() -> UsageMenuCardView.Model.Metric {
        var metric = UsageMenuCardView.Model.Metric(
            id: "primary",
            title: "Weekly",
            percent: 40,
            percentStyle: .left,
            resetText: "Resets in 3d",
            detailText: nil,
            detailLeftText: "6% in reserve",
            detailRightText: "Lasts until reset",
            pacePercent: 46,
            detailIsPaceDerived: true,
            paceOnTop: true)
        metric.dailyTargetText = "≈ 9% / day"
        return metric
    }

    private static func balanceMetric() -> UsageMenuCardView.Model.Metric {
        UsageMenuCardView.Model.Metric(
            id: "secondary",
            title: "Balance",
            percent: 10,
            percentStyle: .left,
            resetText: nil,
            detailText: nil,
            detailLeftText: "Balance note",
            detailRightText: nil,
            pacePercent: nil,
            paceOnTop: true)
    }

    private static func dashboard(points: Bool) -> InlineUsageDashboardModel {
        let spend: [InlineUsageDashboardModel.Point] = (0..<7).map { day in
            InlineUsageDashboardModel.Point(
                id: "day-\(day)",
                label: "D\(day)",
                value: Double(day + 1),
                accessibilityValue: "")
        }
        return InlineUsageDashboardModel(
            accessibilityLabel: "Spend history",
            valueStyle: .currencyUSD,
            kpis: [InlineUsageDashboardModel.KPI(title: "Today", value: "$1.00", emphasis: true)],
            points: points ? spend : [],
            detailLines: ["Top model: synthetic-model"])
    }

    private static func throughputSnapshot() -> ProviderThroughputSnapshot {
        let minutes = (0..<60).map { index in
            ProviderThroughputSnapshot.Minute(
                start: Self.now.addingTimeInterval(Double(index - 60) * 60),
                totalTokens: 1000 + index,
                requests: 5,
                isPending: false)
        }
        return ProviderThroughputSnapshot(
            minutes: minutes,
            frontier: minutes.last?.start,
            latestTokensPerMinute: 1059,
            peakTokensPerMinute: 1059,
            peakAt: minutes.last?.start,
            fiveMinuteAverageTokensPerMinute: 1050,
            models: [],
            windowMinutes: 60,
            fetchedAt: Self.now,
            projectID: nil)
    }

    /// Three weekly windows on one reset lattice: the oldest capped, the middle one settled, the last current.
    private static func weeklyHistory() -> PlanUtilizationSeriesHistory {
        let week: TimeInterval = 7 * 24 * 60 * 60
        let currentReset = Self.now.addingTimeInterval(2 * 24 * 60 * 60)
        let entries = [
            PlanUtilizationHistoryEntry(
                capturedAt: currentReset.addingTimeInterval(-2 * week - 3600),
                usedPercent: 100,
                resetsAt: currentReset.addingTimeInterval(-2 * week)),
            PlanUtilizationHistoryEntry(
                capturedAt: currentReset.addingTimeInterval(-week - 3600),
                usedPercent: 50,
                resetsAt: currentReset.addingTimeInterval(-week)),
            PlanUtilizationHistoryEntry(
                capturedAt: Self.now.addingTimeInterval(-24 * 60 * 60),
                usedPercent: 20,
                resetsAt: currentReset),
            PlanUtilizationHistoryEntry(capturedAt: Self.now, usedPercent: 35, resetsAt: currentReset),
        ]
        return PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: entries)
    }
}
