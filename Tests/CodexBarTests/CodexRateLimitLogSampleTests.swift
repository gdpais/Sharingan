import Foundation
import Testing
@testable import CodexBarCore

struct CodexRateLimitLogSampleTests {
    /// 2026-10-01T10:15:00Z
    private static let eventEpoch: TimeInterval = 1_790_849_700
    /// 2026-10-01T14:00:00Z, inside the 5-hour window that started before the event.
    private static let sessionResetEpoch: TimeInterval = 1_790_863_200
    /// 2026-10-07T00:00:00Z
    private static let weeklyResetEpoch: TimeInterval = 1_791_331_200
    /// 2026-10-02T12:00:00Z
    private static let scanNow = Date(timeIntervalSince1970: 1_790_942_400)

    private static func tokenCountLine(timestamp: String, rateLimits: String) -> String {
        let parts: [String] = [
            #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","#,
            #""info":{"total_token_usage":{"input_tokens":10,"output_tokens":2}},"#,
            #""rate_limits":\#(rateLimits)}}"#,
        ]
        return parts.joined()
    }

    private static func currentRateLimits(primaryPercent: Double, secondaryPercent: Double = 12) -> String {
        let sessionReset = Int(Self.sessionResetEpoch)
        let weeklyReset = Int(Self.weeklyResetEpoch)
        let parts: [String] = [
            #"{"limit_id":"codex","limit_name":null,"#,
            #""primary":{"used_percent":\#(primaryPercent),"window_minutes":300,"resets_at":\#(sessionReset)},"#,
            #""secondary":{"used_percent":\#(secondaryPercent),"window_minutes":10080,"resets_at":\#(weeklyReset)},"#,
            #""credits":null,"plan_type":"plus"}"#,
        ]
        return parts.joined()
    }

    private static func sample(_ line: String) -> CodexRateLimitLogSample? {
        CostUsageScanner.codexRateLimitSample(fromLine: Data(line.utf8))
    }

    @Test
    func `decodes primary and secondary windows from a token count event`() throws {
        let line = Self.tokenCountLine(
            timestamp: "2026-10-01T10:15:00.250Z",
            rateLimits: Self.currentRateLimits(primaryPercent: 42.5))

        let sample = try #require(Self.sample(line))

        #expect(sample.observedAt == Date(timeIntervalSince1970: Self.eventEpoch + 0.25))
        #expect(sample.primary == CodexRateLimitLogWindow(
            usedPercent: 42.5,
            windowMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: Self.sessionResetEpoch)))
        #expect(sample.secondary == CodexRateLimitLogWindow(
            usedPercent: 12,
            windowMinutes: 10080,
            resetsAt: Date(timeIntervalSince1970: Self.weeklyResetEpoch)))
        #expect(sample.creatorAccountID == nil)
    }

    @Test
    func `converts resets in seconds relative to the event timestamp`() throws {
        // Older Codex CLI builds logged seconds-to-reset and no limit id.
        let line = Self.tokenCountLine(
            timestamp: "2026-10-01T10:15:00Z",
            rateLimits: #"{"primary":{"used_percent":7,"window_minutes":299,"resets_in_seconds":1800},"#
                + #""secondary":{"used_percent":55.5,"window_minutes":10080,"resets_in_seconds":259200}}"#)

        let sample = try #require(Self.sample(line))
        let observedAt = Date(timeIntervalSince1970: Self.eventEpoch)

        #expect(sample.observedAt == observedAt)
        #expect(sample.primary?.usedPercent == 7)
        #expect(sample.primary?.windowMinutes == 299)
        #expect(sample.primary?.resetsAt == observedAt.addingTimeInterval(1800))
        #expect(sample.secondary?.usedPercent == 55.5)
        #expect(sample.secondary?.resetsAt == observedAt.addingTimeInterval(259_200))
    }

    @Test
    func `ignores lines without a usable default rate limit snapshot`() {
        let timestamp = "2026-10-01T10:15:00Z"
        let nullRateLimits = Self.tokenCountLine(timestamp: timestamp, rateLimits: "null")
        let infoOnly = #"{"timestamp":"2026-10-01T10:15:00Z","type":"event_msg","#
            + #""payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1}}}}"#
        let otherEvent = #"{"timestamp":"2026-10-01T10:15:00Z","type":"turn_context","#
            + #""payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5,"window_minutes":300}}}}"#
        let modelSpecific = Self.tokenCountLine(
            timestamp: timestamp,
            rateLimits: #"{"limit_id":"codex_bengalfox","primary":{"used_percent":5,"window_minutes":300}}"#)
        let missingPercent = Self.tokenCountLine(
            timestamp: timestamp,
            rateLimits: #"{"primary":{"window_minutes":300,"resets_at":1790863200},"secondary":null}"#)
        let badTimestamp = Self.tokenCountLine(
            timestamp: "yesterday",
            rateLimits: Self.currentRateLimits(primaryPercent: 5))

        for line in [nullRateLimits, infoOnly, otherEvent, modelSpecific, missingPercent, badTimestamp] {
            #expect(Self.sample(line) == nil)
        }
    }

    @Test
    func `drops windows whose reset already passed or is implausibly far away`() throws {
        let timestamp = "2026-10-01T10:15:00Z"
        let staleSession = Self.tokenCountLine(
            timestamp: timestamp,
            rateLimits: #"{"primary":{"used_percent":90,"window_minutes":300,"resets_at":1790849640},"#
                + #""secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1791331200}}"#)
        let sample = try #require(Self.sample(staleSession))
        #expect(sample.primary == nil)
        #expect(sample.secondary?.usedPercent == 20)

        // Milliseconds instead of seconds put the boundary far past the 5-hour window.
        let milliseconds = Self.tokenCountLine(
            timestamp: timestamp,
            rateLimits: #"{"primary":{"used_percent":30,"window_minutes":300,"resets_at":1790863200000}}"#)
        #expect(Self.sample(milliseconds) == nil)

        let allStale = Self.tokenCountLine(
            timestamp: timestamp,
            rateLimits: #"{"primary":{"used_percent":90,"window_minutes":300,"resets_in_seconds":0}}"#)
        #expect(Self.sample(allStale) == nil)
    }

    @Test
    func `scans session and archived rollouts with creator attribution`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-rate-limit-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let dayDirectory = home.appendingPathComponent("sessions/2026/10/01", isDirectory: true)
        let archivedDirectory = home.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedDirectory, withIntermediateDirectories: true)

        func reading(_ timestamp: String, primaryPercent: Double) -> String {
            Self.tokenCountLine(
                timestamp: timestamp,
                rateLimits: Self.currentRateLimits(primaryPercent: primaryPercent))
        }
        let activeLines: [String] = [
            #"{"timestamp":"2026-10-01T10:00:00Z","type":"session_meta","#
                + #""payload":{"id":"thread-a","creator_account_id":"  Acct-ABC  ","cwd":"/tmp/project"}}"#,
            reading("2026-10-01T10:15:00Z", primaryPercent: 10),
            // Identical reading later in the same hour: only the latest is kept.
            reading("2026-10-01T10:20:00Z", primaryPercent: 10),
            reading("2026-10-01T10:40:00Z", primaryPercent: 12),
            Self.tokenCountLine(timestamp: "2026-10-01T10:45:00Z", rateLimits: "null"),
            // Copied ancestor metadata never reassigns the rollout's creator.
            #"{"timestamp":"2026-10-01T10:50:00Z","type":"session_meta","#
                + #""payload":{"id":"thread-parent","creator_account_id":"acct-other"}}"#,
            "not json",
        ]
        try activeLines.joined(separator: "\n").write(
            to: dayDirectory.appendingPathComponent("rollout-2026-10-01T10-00-00-a.jsonl"),
            atomically: true,
            encoding: .utf8)

        let archivedLines: [String] = [
            #"{"timestamp":"2026-09-30T08:00:00Z","type":"session_meta","payload":{"id":"thread-b"}}"#,
            // Older than the scan horizon.
            Self.tokenCountLine(
                timestamp: "2026-08-01T08:05:00Z",
                rateLimits: #"{"primary":{"used_percent":99,"window_minutes":300,"resets_in_seconds":600}}"#),
            Self.tokenCountLine(
                timestamp: "2026-09-30T08:05:00Z",
                rateLimits: #"{"primary":{"used_percent":3,"window_minutes":300,"resets_in_seconds":600}}"#),
        ]
        try (archivedLines.joined(separator: "\n") + "\n").write(
            to: archivedDirectory.appendingPathComponent("rollout-2026-09-30T08-00-00-b.jsonl"),
            atomically: true,
            encoding: .utf8)

        let horizon = Self.scanNow.addingTimeInterval(-30 * 24 * 60 * 60)
        let scan = CodexRateLimitLogScanner.scan(
            codexHomePath: home.path,
            modifiedSince: nil,
            horizon: horizon,
            now: Self.scanNow)

        #expect(scan.isComplete)
        #expect(scan.samples.map(\.observedAt) == [
            Date(timeIntervalSince1970: 1_790_755_500),
            Date(timeIntervalSince1970: 1_790_850_000),
            Date(timeIntervalSince1970: 1_790_851_200),
        ])
        #expect(scan.samples.map(\.creatorAccountID) == [nil, "acct-abc", "acct-abc"])
        #expect(scan.samples.map { $0.primary?.usedPercent } == [3, 10, 12])

        let alreadyRead = CodexRateLimitLogScanner.scan(
            codexHomePath: home.path,
            modifiedSince: .distantFuture,
            horizon: horizon,
            now: Self.scanNow)
        #expect(alreadyRead == .empty)
    }
}
