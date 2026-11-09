import Foundation
import SharinganCore
import Testing
@testable import Sharingan

struct SpendDashboardMidnightDSTTests {
    @Test(arguments: [6, 7, 11], [false, true])
    func `native model preserves daily keys across midnight DST`(
        septemberDay: Int,
        completeHistory: Bool) throws
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: septemberDay, hour: 12)))
        let dates = try (0..<365).map { offset in
            let date = try #require(calendar.date(byAdding: .day, value: -offset, to: now))
            return calendar.startOfDay(for: date)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let entries = dates.enumerated().map { offset, day in
            CostUsageDailyReport.Entry(
                date: formatter.string(from: day),
                inputTokens: offset + 1,
                outputTokens: 0,
                totalTokens: offset + 1,
                costUSD: 0,
                modelsUsed: nil,
                modelBreakdowns: nil)
        }
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: completeHistory ? (1...365).reduce(0, +) : nil,
            last30DaysCostUSD: nil,
            historyDays: 365,
            daily: entries,
            updatedAt: now)
        for requestedDays in [7, 30, 365] {
            let model = SpendDashboardModel.build(
                inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
                requestedDays: requestedDays,
                now: now,
                calendar: calendar)
            #expect(model.tokenActivity.map(\.day) == Array(dates.reversed()))
            #expect(model.tokenActivity.compactMap(\.totalTokens) == Array((1...365).reversed()))
            let group = try #require(model.groups.first)
            #expect(group.dailySummaries.map(\.day) == Array(dates.prefix(requestedDays).reversed()))
            #expect(group.totalTokens == (1...requestedDays).reduce(0, +))
            if completeHistory {
                #expect(group.coveredDayCount == requestedDays)
                #expect(group.dailySummaries.compactMap(\.totalTokens) == Array((1...requestedDays).reversed()))
            }
            let series = SpendActivitySeries.make(from: model.tokenActivity, now: now, calendar: calendar)
            #expect(series.visibleDayCount == 365)
            #expect(series.coveredDayCount == 365)
            #expect(series.daily.reduce(0, +) == (1...365).reduce(0, +))
        }
    }

    @Test
    func `coverage and chart bounds use complete civil days around midnight DST`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let transition = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12)))
        let next = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)))
        let nextStart = calendar.startOfDay(for: next)
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 1,
            sessionCostUSD: 1,
            last30DaysTokens: 2,
            last30DaysCostUSD: 2,
            historyDays: 2,
            historyCoverageIsEstablished: true,
            daily: ["2026-09-06", "2026-09-07"].map {
                .init(
                    date: $0,
                    inputTokens: 1,
                    outputTokens: 0,
                    totalTokens: 1,
                    costUSD: 1,
                    modelsUsed: nil,
                    modelBreakdowns: nil)
            },
            updatedAt: next)
        let covered = SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Synthetic Codex", snapshot: snapshot)],
            requestedDays: 2,
            now: next,
            calendar: calendar)
        #expect(covered.groups.first?.coveredDayCount == 2)
        #expect(covered.groups.first?.providers.first?.coveredDayCount == 2)
        let selected = SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Synthetic Codex", snapshot: snapshot)],
            requestedDays: 2,
            now: transition,
            calendar: calendar,
            selectedDay: transition)
        #expect(selected.groups.first?.chartDomain.upperBound == nextStart)
        let group = try #require(selected.groups.first)
        #expect(SpendTrendChartModel(group: group, section: .hourly, day: transition).domain.upperBound == nextStart)
    }
}

struct SpendDashboardDayCountDSTTests {
    @Test(arguments: [
        // Autumn change (25 Oct 2026) and spring change (29 Mar 2026) inside the 30-day scan.
        DateComponents(year: 2026, month: 11, day: 9, hour: 12),
        DateComponents(year: 2026, month: 4, day: 15, hour: 12),
    ])
    func `covered day count stays exact when the window crosses a Lisbon DST change`(
        nowComponents: DateComponents) throws
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Lisbon"))
        let now = try #require(calendar.date(from: nowComponents))
        let today = calendar.startOfDay(for: now)
        let start = try #require(calendar.date(byAdding: .day, value: -29, to: today))
        #expect(SpendDashboardModel.dayCount(in: start...today, calendar: calendar) == 30)
        #expect(SpendDashboardModel.dayCount(in: today...now, calendar: calendar) == 1)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 85,
            sessionCostUSD: nil,
            last30DaysTokens: 85,
            last30DaysCostUSD: nil,
            historyDays: 30,
            historyCoverageIsEstablished: true,
            daily: [.init(
                date: formatter.string(from: now),
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: 85,
                costUSD: nil,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            updatedAt: now)
        let model = SpendDashboardModel.build(
            inputs: [.init(provider: .grok, displayName: "Grok", snapshot: snapshot)],
            requestedDays: 60,
            now: now,
            calendar: calendar)
        let row = try #require(model.groups.flatMap(\.providers).first { $0.provider == .grok })
        #expect(row.totalTokens == 85)
        #expect(row.coveredDayCount == 30)
    }
}
