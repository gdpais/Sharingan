import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

@Suite(.serialized, CostUsageClaudeCacheFixtures())
@MainActor
struct CostHistoryPreviousPeriodTests {
    private typealias Entry = CostUsageDailyReport.Entry
    private static let model = "claude-sonnet-4-20250514"

    // MARK: - Request

    @Test
    func `the previous window is the equal window before the history window`() throws {
        let calendar = Self.utcCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        let since = try #require(calendar.date(byAdding: .day, value: -29, to: now))
        let request = try #require(CostUsagePreviousPeriodRequest(
            historyDays: 30, since: since, now: now, calendar: calendar, reportContext: .regular))
        let range = request.range(calendar: calendar)
        #expect(range.sinceKey == "2026-08-02")
        #expect(range.untilKey == "2026-08-31")
        #expect(request.now == now)
    }

    @Test
    func `only rolling windows of a week to a quarter read a previous window`() throws {
        let calendar = Self.utcCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        func request(days: Int, context: CostUsageReportContext? = .regular) -> CostUsagePreviousPeriodRequest? {
            let since = calendar.date(byAdding: .day, value: -(days - 1), to: now) ?? now
            return CostUsagePreviousPeriodRequest(
                historyDays: days, since: since, now: now, calendar: calendar, reportContext: context)
        }
        #expect(request(days: 7) != nil)
        #expect(request(days: 90) != nil)
        #expect(request(days: 30, context: nil) != nil)
        #expect(request(days: 6) == nil)
        #expect(request(days: 1) == nil)
        #expect(request(days: 365) == nil)
        // The Usage & Spend window keeps its own wide cache.
        #expect(request(days: 30, context: .spendDashboard) == nil)
    }

    @Test
    func `transcripts cover a window only when one was written before it`() throws {
        let calendar = Self.utcCalendar
        let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12)))
        let onStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 1)))
        func covers(_ date: Date?) -> Bool {
            CostUsagePreviousPeriod.transcriptsCover(
                sinceKey: "2026-08-02",
                oldestTranscriptWriteUnixMs: date.map { Int64($0.timeIntervalSince1970 * 1000) },
                calendar: calendar)
        }
        #expect(covers(before))
        #expect(!covers(onStart))
        #expect(!covers(nil))
    }

    // MARK: - Claude transcripts

    @Test
    func `retaining the previous window keeps the history window report unchanged`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let fixture = try Self.writeTranscripts(env: env, oldestWrite: nil)

        let retained = try CostUsageScanner.loadDailyReportRetainingPreviousPeriod(
            provider: .claude,
            since: fixture.since,
            until: fixture.now,
            now: fixture.now,
            options: fixture.options,
            reportContext: nil,
            retainSince: fixture.request.since,
            checkCancellation: nil)
        #expect(retained.data.map(\.date) == [fixture.currentDay])
        #expect(retained.summary?.totalTokens == 110)

        let cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot)
        let scanSince = try #require(cache.usage.scanSinceKey)
        #expect(scanSince <= fixture.request.range(calendar: .current).sinceKey)
    }

    @Test
    func `the previous window is read when an older transcript proves it was kept`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let fixture = try Self.writeTranscripts(env: env, oldestWrite: Self.daysBefore(40))
        _ = try Self.scan(fixture)

        let previous = try #require(CostUsageScanner.loadClaudePreviousPeriodReport(
            provider: .claude,
            request: fixture.request,
            options: fixture.options,
            reportContext: nil))
        #expect(previous.data.map(\.date) == [fixture.previousDay])
        #expect(previous.summary?.totalTokens == 44)
        #expect(CostUsageFetcher.claudePreviousPeriodDaily(
            provider: .claude, request: fixture.request, options: fixture.options, reportContext: nil)?
            .map(\.date) == [fixture.previousDay])
    }

    @Test
    func `the previous window stays unread when transcripts may have been cleaned up`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        // Every transcript was last written inside the windows, so older ones may have been deleted.
        let fixture = try Self.writeTranscripts(env: env, oldestWrite: Self.daysBefore(2))
        _ = try Self.scan(fixture)

        #expect(CostUsageScanner.loadClaudePreviousPeriodReport(
            provider: .claude,
            request: fixture.request,
            options: fixture.options,
            reportContext: nil) == nil)
        #expect(CostUsageFetcher.claudePreviousPeriodDaily(
            provider: .codex, request: fixture.request, options: fixture.options, reportContext: nil) == nil)
        #expect(CostUsageFetcher.claudePreviousPeriodDaily(
            provider: .claude, request: nil, options: fixture.options, reportContext: nil) == nil)
    }

    @Test
    func `a scan of the history window alone has no previous window`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let fixture = try Self.writeTranscripts(env: env, oldestWrite: Self.daysBefore(40))
        _ = try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude,
            since: fixture.since,
            until: fixture.now,
            now: fixture.now,
            options: fixture.options,
            checkCancellation: nil)

        #expect(CostUsageScanner.loadClaudePreviousPeriodReport(
            provider: .claude,
            request: fixture.request,
            options: fixture.options,
            reportContext: nil) == nil)
    }

    // MARK: - Cost history gating

    @Test
    func `cost history compares only rolling windows read in full`() throws {
        let calendar = Self.utcCalendar
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12)))
        var snapshot = Self.snapshot(now: now, historyDays: 7, covered: true)
        snapshot.previousPeriodDaily = [
            Self.entry("2026-09-17", cost: 4),
            Self.entry("2026-09-23", cost: 6),
        ]
        #expect(CostHistoryChartMenuView.previousPeriodCostUSD(snapshot, historyDays: 7, calendar: calendar) == 10)

        // Month to date and all time are not rolling windows.
        #expect(CostHistoryChartMenuView.previousPeriodCostUSD(
            snapshot.reporting(.monthToDate), historyDays: 7, calendar: calendar) == nil)
        #expect(CostHistoryChartMenuView.previousPeriodCostUSD(
            snapshot.reporting(.allTime), historyDays: 7, calendar: calendar) == nil)

        var partial = Self.snapshot(now: now, historyDays: 7, covered: false)
        partial.previousPeriodDaily = snapshot.previousPeriodDaily
        #expect(CostHistoryChartMenuView.previousPeriodCostUSD(partial, historyDays: 7, calendar: calendar) == nil)

        let unread = Self.snapshot(now: now, historyDays: 7, covered: true)
        #expect(CostHistoryChartMenuView.previousPeriodCostUSD(unread, historyDays: 7, calendar: calendar) == nil)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let now: Date
        let since: Date
        let request: CostUsagePreviousPeriodRequest
        let options: CostUsageScanner.Options
        let currentDay: String
        let previousDay: String
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func daysBefore(_ days: Int) -> (Date) -> Date {
        { now in Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now }
    }

    /// A 7-day window ending 2026-09-30: one request on 09-25 (current window), one on 09-20 (previous
    /// window) and one on 09-01, before both. `oldestWrite` dates an extra, older transcript.
    private static func writeTranscripts(
        env: CostUsageTestEnvironment,
        oldestWrite: ((Date) -> Date)?) throws -> Fixture
    {
        let now = try env.makeLocalNoon(year: 2026, month: 9, day: 30)
        let since = try #require(Calendar.current.date(byAdding: .day, value: -6, to: now))
        let current = try env.makeLocalNoon(year: 2026, month: 9, day: 25)
        let previous = try env.makeLocalNoon(year: 2026, month: 9, day: 20)
        let older = try env.makeLocalNoon(year: 2026, month: 9, day: 1)
        let transcript = try env.writeClaudeProjectFile(
            relativePath: "project/session.jsonl",
            contents: env.jsonl([
                self.assistant(env: env, day: older, id: "older", input: 7),
                self.assistant(env: env, day: previous, id: "previous", input: 40, output: 4),
                self.assistant(env: env, day: current, id: "current", input: 100, output: 10),
            ]))
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: transcript.path)
        if let oldestWrite {
            let old = try env.writeClaudeProjectFile(
                relativePath: "project/old-session.jsonl",
                contents: env.jsonl([self.assistant(env: env, day: older, id: "old-session", input: 0, output: 0)]))
            try FileManager.default.setAttributes([.modificationDate: oldestWrite(now)], ofItemAtPath: old.path)
        }
        var options = CostUsageScanner.Options(claudeProjectsRoots: [env.claudeProjectsRoot], cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0
        let request = try #require(CostUsagePreviousPeriodRequest(
            historyDays: 7, since: since, now: now, calendar: .current, reportContext: nil))
        return Fixture(
            now: now,
            since: since,
            request: request,
            options: options,
            currentDay: "2026-09-25",
            previousDay: "2026-09-20")
    }

    private static func scan(_ fixture: Fixture) throws -> CostUsageDailyReport {
        try CostUsageScanner.loadDailyReportRetainingPreviousPeriod(
            provider: .claude,
            since: fixture.since,
            until: fixture.now,
            now: fixture.now,
            options: fixture.options,
            reportContext: nil,
            retainSince: fixture.request.since,
            checkCancellation: nil)
    }

    private static func assistant(
        env: CostUsageTestEnvironment,
        day: Date,
        id: String,
        input: Int,
        output: Int = 0) -> [String: Any]
    {
        [
            "type": "assistant",
            "timestamp": env.isoString(for: day),
            "sessionId": "session-\(id)",
            "requestId": "request-\(id)",
            "message": [
                "id": "message-\(id)",
                "model": self.model,
                "usage": ["input_tokens": input, "output_tokens": output],
            ],
        ]
    }

    private static func snapshot(now: Date, historyDays: Int, covered: Bool) -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: 12,
            historyDays: historyDays,
            historyCoverageIsEstablished: covered,
            daily: [self.entry("2026-09-30", cost: 12)],
            updatedAt: now)
    }

    private static func entry(_ date: String, cost: Double) -> Entry {
        Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }
}
