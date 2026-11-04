import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct QuotaBurndownModelTests {
    @Test
    func `builds current window samples and ideal line`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let history = Self.history(entries: [
            Self.entry(hoursBeforeNow: 2, usedPercent: 20, reset: reset),
            Self.entry(hoursBeforeNow: 1, usedPercent: 45, reset: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 60, reset: reset),
            now: Self.now))

        #expect(model.start == reset.addingTimeInterval(-5 * 3600))
        #expect(model.reset == reset)
        #expect(model.samples == [
            .init(date: Self.now.addingTimeInterval(-2 * 3600), remainingPercent: 80),
            .init(date: Self.now.addingTimeInterval(-3600), remainingPercent: 55),
            .init(date: Self.now, remainingPercent: 40),
        ])
        #expect(model.ideal == [
            .init(date: reset.addingTimeInterval(-5 * 3600), remainingPercent: 100),
            .init(date: reset, remainingPercent: 0),
        ])
    }

    @Test
    func `isolates the current reset and keeps only the newest segment after a usage drop`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let priorReset = reset.addingTimeInterval(-5 * 3600)
        let history = Self.history(entries: [
            Self.entry(hoursBeforeNow: 6, usedPercent: 90, reset: priorReset),
            Self.entry(hoursBeforeNow: 4, usedPercent: 70, reset: reset),
            Self.entry(hoursBeforeNow: 2, usedPercent: 80, reset: reset),
            Self.entry(hoursBeforeNow: 1.5, usedPercent: 85, reset: priorReset),
            Self.entry(hoursBeforeNow: 1, usedPercent: 10, reset: reset),
            Self.entry(hoursBeforeNow: 0.5, usedPercent: 25, reset: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 30, reset: reset),
            now: Self.now))

        #expect(model.samples == [
            .init(date: Self.now.addingTimeInterval(-3600), remainingPercent: 90),
            .init(date: Self.now.addingTimeInterval(-1800), remainingPercent: 75),
            .init(date: Self.now, remainingPercent: 70),
        ])
    }

    @Test
    func `accepts small reset timestamp drift while excluding another cycle`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let history = Self.history(entries: [
            Self.entry(hoursBeforeNow: 2, usedPercent: 20, reset: reset.addingTimeInterval(90)),
            Self.entry(hoursBeforeNow: 1, usedPercent: 40, reset: reset.addingTimeInterval(-5 * 3600)),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 50, reset: reset),
            now: Self.now))

        #expect(model.samples == [
            .init(date: Self.now.addingTimeInterval(-2 * 3600), remainingPercent: 80),
            .init(date: Self.now, remainingPercent: 50),
        ])
    }

    @Test
    func `requires a valid current reset and duration`() {
        let history = Self.history(entries: [])

        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(
                usedPercent: 10,
                windowMinutes: 0,
                resetsAt: Self.now.addingTimeInterval(3600),
                resetDescription: nil),
            now: Self.now) == nil)
        #expect(QuotaBurndownModel(
            history: history,
            window: RateWindow(
                usedPercent: 10,
                windowMinutes: 300,
                resetsAt: Self.now.addingTimeInterval(3600),
                resetDescription: nil,
                isSyntheticPlaceholder: true),
            now: Self.now) == nil)
    }

    @Test
    func `uses the live window when history has no current samples`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let history = Self.history(entries: [
            Self.entry(hoursBeforeNow: 6, usedPercent: 80, reset: reset.addingTimeInterval(-5 * 3600)),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 125, reset: reset),
            now: Self.now))

        #expect(model.samples == [.init(date: Self.now, remainingPercent: 0)])
    }

    @Test
    func `deduplicates timestamps skips nonfinite history and rejects nonfinite live usage`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)
        let duplicateDate = Self.now.addingTimeInterval(-3600)
        let history = Self.history(entries: [
            .init(capturedAt: Self.now.addingTimeInterval(-2 * 3600), usedPercent: .nan, resetsAt: reset),
            .init(capturedAt: duplicateDate, usedPercent: 20, resetsAt: reset),
            .init(capturedAt: duplicateDate, usedPercent: 30, resetsAt: reset),
            .init(capturedAt: Self.now, usedPercent: 40, resetsAt: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: 150, reset: reset),
            now: Self.now))

        #expect(model.samples == [
            .init(date: duplicateDate, remainingPercent: 70),
            .init(date: Self.now, remainingPercent: 0),
        ])
        #expect(QuotaBurndownModel(
            history: history,
            window: Self.window(usedPercent: .infinity, reset: reset),
            now: Self.now) == nil)
    }

    @Test
    func `work day ideal agrees with the pace deficit`() throws {
        let calendar = Self.utcCalendar
        // Mon Jun 8 2026 09:00 → Mon Jun 15 2026 09:00, checked Wed Jun 10 15:00 at 52% used.
        let start = try Self.utcDate(day: 8, hour: 9)
        let reset = start.addingTimeInterval(7 * 24 * 3600)
        let now = try Self.utcDate(day: 10, hour: 15)
        let window = RateWindow(usedPercent: 52, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)
        let tuesday = try Self.utcDate(day: 9, hour: 12)
        let history = PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [
            .init(capturedAt: tuesday, usedPercent: 30, resetsAt: reset),
        ])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: window,
            now: now,
            workDays: 5,
            calendar: calendar))
        let pace = try #require(UsagePace.weekly(window: window, now: now, workDays: 5, calendar: calendar))

        // 54 of 120 work hours have elapsed: 45% expected used, so the ideal sits at 55% remaining.
        let idealAtNow = try #require(Self.interpolatedRemaining(model.ideal, at: now))
        let observedAtNow = try #require(model.samples.last?.remainingPercent)
        #expect(abs(idealAtNow - 55) < 0.0001)
        #expect(abs((idealAtNow - observedAtNow) - pace.deltaPercent) < 0.0001)
        #expect(abs(pace.deltaPercent - 7) < 0.0001)

        let runOut = try #require(model.runOut)
        let etaSeconds = try #require(pace.etaSeconds)
        #expect(abs(runOut.timeIntervalSince(now) - etaSeconds) < 0.001)
        #expect(runOut < reset)
        #expect(model.now == now)
        #expect(model.projection.first == .init(date: now, remainingPercent: 48))
        #expect(model.projection.last == .init(date: runOut, remainingPercent: 0))
    }

    @Test
    func `work day ideal stays flat over the weekend`() throws {
        let start = try Self.utcDate(day: 8, hour: 9)
        let reset = start.addingTimeInterval(7 * 24 * 3600)
        let now = try Self.utcDate(day: 10, hour: 15)
        let history = PlanUtilizationSeriesHistory(name: .weekly, windowMinutes: 10080, entries: [])

        let model = try #require(QuotaBurndownModel(
            history: history,
            window: RateWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: reset, resetDescription: nil),
            now: now,
            workDays: 5,
            calendar: Self.utcCalendar))

        let weekend = try [13, 14, 15].map { try Self.utcDate(day: $0, hour: 0) }
        let weekendRemaining = weekend.compactMap { date in
            model.ideal.first { $0.date == date }?.remainingPercent
        }
        #expect(weekendRemaining.count == 3)
        #expect(weekendRemaining.allSatisfy { abs($0 - 7.5) < 0.0001 })
        #expect(model.ideal.first == .init(date: start, remainingPercent: 100))
        #expect(model.ideal.last == .init(date: reset, remainingPercent: 0))
        #expect(model.runOut == nil)
        #expect(model.projection.last?.date == reset)
    }

    @Test
    func `work days do not bend non weekly ideals`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)

        let model = try #require(QuotaBurndownModel(
            history: Self.history(entries: []),
            window: Self.window(usedPercent: 60, reset: reset),
            now: Self.now,
            workDays: 5,
            calendar: Self.utcCalendar))

        #expect(model.ideal == [
            .init(date: reset.addingTimeInterval(-5 * 3600), remainingPercent: 100),
            .init(date: reset, remainingPercent: 0),
        ])
    }

    @Test
    func `exhausted quota runs out now`() throws {
        let reset = Self.now.addingTimeInterval(2 * 3600)

        let model = try #require(QuotaBurndownModel(
            history: Self.history(entries: []),
            window: Self.window(usedPercent: 100, reset: reset),
            now: Self.now))

        #expect(model.runOut == Self.now)
        #expect(model.projection == [.init(date: Self.now, remainingPercent: 0)])
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func utcDate(day: Int, hour: Int) throws -> Date {
        try #require(self.utcCalendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: day,
            hour: hour)))
    }

    private static func interpolatedRemaining(
        _ points: [QuotaBurndownModel.Sample],
        at date: Date) -> Double?
    {
        guard let upperIndex = points.firstIndex(where: { $0.date > date }), upperIndex > 0 else { return nil }
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let fraction = date.timeIntervalSince(lower.date) / upper.date.timeIntervalSince(lower.date)
        return lower.remainingPercent + (upper.remainingPercent - lower.remainingPercent) * fraction
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func history(entries: [PlanUtilizationHistoryEntry]) -> PlanUtilizationSeriesHistory {
        PlanUtilizationSeriesHistory(name: .session, windowMinutes: 300, entries: entries)
    }

    private static func entry(
        hoursBeforeNow: Double,
        usedPercent: Double,
        reset: Date?) -> PlanUtilizationHistoryEntry
    {
        PlanUtilizationHistoryEntry(
            capturedAt: self.now.addingTimeInterval(-hoursBeforeNow * 3600),
            usedPercent: usedPercent,
            resetsAt: reset)
    }

    private static func window(usedPercent: Double, reset: Date) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            windowMinutes: 300,
            resetsAt: reset,
            resetDescription: nil)
    }
}
