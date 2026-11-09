import CryptoKit
import Foundation
import Testing
@testable import SharinganCore

@Suite(.serialized, CostUsageClaudeCacheFixtures())
struct CostUsageClaudeReconciliationMemoryTests {
    @Test
    func `winner payload contains only two indexes`() {
        let priorStride = MemoryLayout<(path: String, row: CostUsageScanner.ClaudeUsageRow)>.stride
        #expect(CostUsageScanner.claudeWinnerPayloadStride == 2 * MemoryLayout<Int>.stride)
        #expect(CostUsageScanner.claudeWinnerPayloadStride * 10 < priorStride)
    }

    /// Golden bytes captured from the row-copy implementation, including both temporal projections.
    @Test(arguments: 0..<4)
    func `randomized duplicate order preserves exact output`(seed: Int) throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        var generator = Generator(state: UInt64(seed))
        var cache = CostUsageClaudeRebuildTests.cache(fileCount: 64, rowsPerFile: 50, includeOverflow: true)
        let files = cache.files.sorted { $0.key < $1.key }.shuffled(using: &generator)
        cache.files = [:]
        for (path, var file) in files {
            file.claudeRows?.shuffle(using: &generator)
            cache.files[path] = file
        }
        cache.files["empty"] = .init(mtimeUnixMs: 0, size: 0, days: [:], claudeRows: [])
        let rows = CostUsageScanner.reconciledClaudeRows(cache: cache)
        CostUsageScanner.rebuildClaudeDays(cache: &cache, rows: rows)
        let report = CostUsageScanner.buildClaudeReportFromCache(
            cache: cache,
            range: CostUsageClaudeRebuildTests.range,
            now: CostUsageClaudeRebuildTests.now,
            modelsDevCacheRoot: env.cacheRoot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try [
            encoder.encode(rows), encoder.encode(cache.days), encoder.encode(report),
            encoder.encode(report.hourly.map(CostUsageCodexPreviousReport.HourlyEntry.init)),
            encoder.encode(report.quotaSlices.map(CostUsageCodexPreviousReport.QuotaSlice.init)),
        ]
        let digest = try SHA256.hash(data: encoder.encode(bytes)).map { String(format: "%02x", $0) }.joined()
        let expected = [
            "65f548c19bcca0f021147a8a108a92a712ad76ebed26787ea85388fb3485a0e1",
            "866cc469f7084c70e2ba066bb65f237d496c17fe513df82330df53dc21bb3503",
            "1393a078e1a3cdb4a061924c774771a2fb4305180d5fdf41b8d7fb5923c97529",
            "2b79b81e98ea90cc8a84e9b61cc54fcaa21d1d8a1f9153b0edc84c2ef34b2511",
        ]
        #expect(digest == expected[seed])
        #expect(cache.days["2026-09-01"]?["fixture/overflow"] == nil)
    }

    @Test
    func `cancellation after reconciliation leaves the cache and memo intact`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let now = CostUsageClaudeRebuildTests.now
        _ = try env.writeClaudeProjectFile(relativePath: "project/session.jsonl", contents: """
        {"type":"assistant","timestamp":"2026-09-30T12:00:00Z","requestId":"fixture-request",
        "message":{"id":"fixture-message","model":"claude-sonnet-4-6",
        "usage":{"input_tokens":10,"output_tokens":1}}}
        """.replacingOccurrences(of: "\n", with: "") + "\n")
        var options = CostUsageScanner.Options(
            claudeProjectsRoots: [env.claudeProjectsRoot],
            cacheRoot: env.cacheRoot,
            calendar: CostUsageClaudeRebuildTests.range.calendar)
        options.refreshMinIntervalSeconds = 0
        let prior = try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude, since: now, until: now, now: now, options: options, checkCancellation: nil)
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: env.cacheRoot)
        let memoURL = CostUsageClaudeReportMemo.reportMemoFileURL(cacheFileURL: cacheURL)
        let before = try [Data(contentsOf: cacheURL), Data(contentsOf: memoURL)]
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        options.forceRescan = true
        #expect(throws: CancellationError.self) {
            try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
                _ = try CostUsageScanner.loadDailyReportCancellable(
                    provider: .claude,
                    since: now,
                    until: now,
                    now: now,
                    options: options,
                    checkCancellation: {
                        if recorder.snapshot().reconciliations > 0 { throw CancellationError() }
                    })
            }
        }
        #expect(recorder.snapshot().reconciliations == 1)
        #expect(try [Data(contentsOf: cacheURL), Data(contentsOf: memoURL)] == before)
        options.forceRescan = false
        let after = try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude, since: now, until: now, now: now, options: options, checkCancellation: nil)
        #expect(after.data == prior.data)
        #expect(after.summary == prior.summary)
        #expect(after.hourly == prior.hourly)
        #expect(after.quotaSlices == prior.quotaSlices)
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            self.state = self.state &* 6_364_136_223_846_793_005 &+ 1
            return self.state
        }
    }
}
