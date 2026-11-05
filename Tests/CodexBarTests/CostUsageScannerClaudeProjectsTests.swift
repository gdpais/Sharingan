import Foundation
import Testing
@testable import CodexBarCore

/// Working-directory paths below never exist, so the git root resolver keeps them as recorded and never spawns git.
@Suite(.serialized, CostUsageClaudeCacheFixtures())
struct CostUsageScannerClaudeProjectsTests {
    private static let model = "claude-sonnet-4-20250514"
    private static let alpha = "/synthetic-claude-projects/alpha"
    private static let beta = "/synthetic-claude-projects/beta"

    @Test
    func `local projects cover Codex and Claude only`() {
        #expect(Set(UsageProvider.allCases.filter(\.supportsLocalProjects)) == [.codex, .claude])
    }

    @Test
    func `sessions in different working directories become separate projects`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 14)
        _ = try env.writeClaudeProjectFile(
            relativePath: "-synthetic-claude-projects-alpha/session-alpha.jsonl",
            contents: env.jsonl([
                Self.assistant(env: env, day: day, id: "alpha-1", cwd: Self.alpha, input: 100, output: 10),
                Self.assistant(env: env, day: day, id: "alpha-2", cwd: Self.alpha, input: 50, output: 5),
            ]))
        _ = try env.writeClaudeProjectFile(
            relativePath: "-synthetic-claude-projects-beta/session-beta.jsonl",
            contents: env.jsonl([
                Self.assistant(env: env, day: day, id: "beta-1", cwd: Self.beta, input: 30, output: 3),
            ]))
        _ = try env.writeClaudeProjectFile(
            relativePath: "unrecorded/session-without-cwd.jsonl",
            contents: env.jsonl([
                Self.assistant(env: env, day: day, id: "chat-1", cwd: nil, input: 7, output: 1),
            ]))
        let options = Self.options(env: env)

        let report = try Self.loadDaily(day: day, options: options)
        let projects = try Self.loadProjects(provider: .claude, day: day, options: options)

        #expect(report.summary?.totalTokens == 206)
        #expect(projects.map(\.path) == [Self.alpha, Self.beta, nil])
        #expect(projects.map(\.name) == ["alpha", "beta", CostUsageProjectBreakdown.unknownProjectName])
        #expect(projects.map(\.totalTokens) == [165, 33, 8])
        #expect(projects.allSatisfy { !$0.isProjectless })
        // Project rows partition the daily report; nothing is double counted or dropped.
        #expect(projects.compactMap(\.totalTokens).reduce(0, +) == report.summary?.totalTokens)
        #expect(projects.map { $0.sources.map(\.path) } == [[Self.alpha], [Self.beta], [nil]])
        #expect(projects.allSatisfy { $0.daily.map(\.date) == report.data.map(\.date) })

        let cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot)
        let alphaUsage = try #require(cache.usage.files.values.first { $0.projectPath == Self.alpha })
        #expect(alphaUsage.canonicalProjectPath == Self.alpha)
        #expect(cache.usage.files.values.count(where: { $0.projectPath == nil }) == 1)
        #expect(try Self.loadProjects(provider: .claude, day: day, options: options) == projects)
    }

    @Test
    func `history without working directories has no project rows`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 14)
        _ = try env.writeClaudeProjectFile(
            relativePath: "unrecorded/session.jsonl",
            contents: env.jsonl([
                Self.assistant(env: env, day: day, id: "chat-1", cwd: nil, input: 7, output: 1),
            ]))
        let options = Self.options(env: env)

        #expect(try Self.loadDaily(day: day, options: options).summary?.totalTokens == 8)
        #expect(try Self.loadProjects(provider: .claude, day: day, options: options).isEmpty)
        #expect(try Self.loadProjects(provider: .vertexai, day: day, options: options).isEmpty)
    }

    @Test
    func `appended lines keep the transcript's first working directory`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 14)
        let url = try env.writeClaudeProjectFile(
            relativePath: "-synthetic-claude-projects-alpha/session.jsonl",
            contents: env.jsonl([
                Self.assistant(env: env, day: day, id: "first", cwd: Self.alpha, input: 100, output: 10),
            ]))
        let options = Self.options(env: env)
        _ = try Self.loadDaily(day: day, options: options)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl([
            Self.assistant(env: env, day: day, id: "second", cwd: Self.beta, input: 20, output: 2),
        ]).utf8))
        try handle.close()
        let recorder = CostUsageScanner.ClaudeScanWorkRecorder()
        let report = try CostUsageScanner.withClaudeScanWorkRecorderForTesting(recorder) {
            try Self.loadDaily(day: day, options: options)
        }
        let projects = try Self.loadProjects(provider: .claude, day: day, options: options)

        #expect(recorder.snapshot().incrementalTranscriptParses == 1)
        #expect(report.summary?.totalTokens == 132)
        #expect(projects.map(\.path) == [Self.alpha])
        #expect(projects.first?.totalTokens == 132)
        let cache = CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot)
        #expect(cache.usage.files.values.map(\.projectPath) == [Self.alpha])
    }

    @Test
    func `resolved roots group working directories and count duplicated responses once`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 14)
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        let shared = Self.row(day: day, range: range, id: "shared", input: 100, output: 10)
        // The same response copied into a subagent transcript loses reconciliation to the parent row.
        let duplicate = Self.row(day: day, range: range, id: "shared", input: 100, output: 10, isSidechain: true)
        var cache = CostUsageCache()
        cache.files["/synthetic/root.jsonl"] = Self.file(
            rows: [shared], projectPath: "/repo", canonicalProjectPath: "/repo")
        cache.files["/synthetic/app.jsonl"] = Self.file(
            rows: [Self.row(day: day, range: range, id: "app", input: 40, output: 4), duplicate],
            projectPath: "/repo/app",
            canonicalProjectPath: "/repo")
        cache.files["/synthetic/other.jsonl"] = Self.file(
            rows: [Self.row(day: day, range: range, id: "other", input: 5, output: 1)],
            projectPath: "/other",
            canonicalProjectPath: "/other")

        let projects = CostUsageScanner.buildClaudeProjectBreakdowns(
            cache: cache,
            range: range,
            pricingResolver: CostUsagePricing.ClaudeResolver(now: day, cacheRoot: env.cacheRoot))

        #expect(projects.map(\.path) == ["/repo", "/other"])
        #expect(projects.map(\.name) == ["repo", "other"])
        #expect(projects.map(\.totalTokens) == [154, 6])
        #expect(projects.first?.sources.map(\.path) == ["/repo", "/repo/app"])
        #expect(projects.first?.sources.map(\.name) == ["repo", "app"])
        #expect(projects.first?.sources.map(\.totalTokens) == [110, 44])
    }

    @Test
    func `Pi rows merged into the Claude total join the unknown project`() async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 14)
        _ = try env.writeClaudeProjectFile(
            relativePath: "-synthetic-claude-projects-alpha/session.jsonl",
            contents: env.jsonl([
                Self.assistant(env: env, day: day, id: "alpha-1", cwd: Self.alpha, input: 100, output: 10),
            ]))
        let piRow: [String: Any] = [
            "type": "message",
            "id": "pi-claude",
            "timestamp": env.isoString(for: day),
            "message": [
                "role": "assistant",
                "provider": "anthropic",
                "model": Self.model,
                "usage": ["input": 20, "output": 5, "totalTokens": 25],
            ],
        ]
        _ = try env.writePiSessionFile(relativePath: "pi-claude.jsonl", contents: env.jsonl([piRow]))
        let ompSessionsRoot = env.root.appendingPathComponent("empty-omp", isDirectory: true)
        try FileManager.default.createDirectory(at: ompSessionsRoot, withIntermediateDirectories: true)
        let environment = ["HOME": env.root.path]
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            ompSessionsRoot: ompSessionsRoot,
            cacheRoot: env.cacheRoot,
            calendar: .current,
            refreshMinIntervalSeconds: 0,
            environment: environment)

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .claude,
            environment: environment,
            now: day,
            historyDays: 1,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            includePiSessions: true,
            scannerOptions: Self.options(env: env),
            piScannerOptions: piOptions)

        #expect(snapshot.last30DaysTokens == 135)
        #expect(snapshot.projects.map(\.path) == [Self.alpha, nil])
        #expect(snapshot.projects.map(\.totalTokens) == [110, 25])
        #expect(snapshot.projects.compactMap(\.totalTokens).reduce(0, +) == snapshot.last30DaysTokens)
    }

    @Test
    func `caches from before working directories rebuild instead of loading`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 14)
        let range = CostUsageScanner.CostUsageDayRange(since: day, until: day)
        var artifact = CostUsageClaudeCache()
        artifact.usage.version = 5
        let legacyRow = Self.row(day: day, range: range, id: "legacy", input: 1, output: 1)
        artifact.usage.files["/synthetic/legacy.jsonl"] = CostUsageFileUsage(
            mtimeUnixMs: 1, size: 1, days: [:], claudeRows: [legacyRow])
        let url = CostUsageClaudeCacheIO.cacheFileURL(provider: .claude, cacheRoot: env.cacheRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(artifact).write(to: url)

        #expect(CostUsageClaudeCacheIO.load(provider: .claude, cacheRoot: env.cacheRoot).usage.files.isEmpty)
    }

    // MARK: - Fixtures

    private static func options(env: CostUsageTestEnvironment) -> CostUsageScanner.Options {
        var options = CostUsageScanner.Options(claudeProjectsRoots: [env.claudeProjectsRoot], cacheRoot: env.cacheRoot)
        options.refreshMinIntervalSeconds = 0
        return options
    }

    private static func loadDaily(day: Date, options: CostUsageScanner.Options) throws -> CostUsageDailyReport {
        try CostUsageScanner.loadDailyReportCancellable(
            provider: .claude,
            since: day,
            until: day,
            now: day,
            options: options,
            checkCancellation: nil)
    }

    private static func loadProjects(
        provider: UsageProvider,
        day: Date,
        options: CostUsageScanner.Options) throws -> [CostUsageProjectBreakdown]
    {
        try CostUsageScanner.loadClaudeProjectBreakdowns(
            provider: provider,
            since: day,
            until: day,
            now: day,
            options: options,
            reportContext: nil,
            checkCancellation: nil)
    }

    private static func assistant(
        env: CostUsageTestEnvironment,
        day: Date,
        id: String,
        cwd: String?,
        input: Int,
        output: Int = 1) -> [String: Any]
    {
        var line: [String: Any] = [
            "type": "assistant",
            "timestamp": env.isoString(for: day),
            "sessionId": "session-\(id)",
            "requestId": "request-\(id)",
            "message": [
                "id": "message-\(id)",
                "model": Self.model,
                "usage": ["input_tokens": input, "output_tokens": output],
            ],
        ]
        if let cwd {
            line["cwd"] = cwd
        }
        return line
    }

    private static func row(
        day: Date,
        range: CostUsageScanner.CostUsageDayRange,
        id: String,
        input: Int,
        output: Int,
        isSidechain: Bool = false) -> CostUsageScanner.ClaudeUsageRow
    {
        CostUsageScanner.ClaudeUsageRow(
            dayKey: range.sinceKey,
            model: self.model,
            sessionId: "session-\(id)",
            messageId: "message-\(id)",
            requestId: "request-\(id)",
            timestampUnixMs: Int64((day.timeIntervalSince1970 * 1000).rounded()),
            isSidechain: isSidechain,
            pathRole: isSidechain ? .subagent : .parent,
            input: input,
            cacheRead: 0,
            cacheCreate: 0,
            cacheCreate1h: 0,
            output: output,
            costNanos: 0,
            costPriced: false)
    }

    private static func file(
        rows: [CostUsageScanner.ClaudeUsageRow],
        projectPath: String,
        canonicalProjectPath: String) -> CostUsageFileUsage
    {
        var usage = CostUsageFileUsage(mtimeUnixMs: 1, size: 1, days: [:], claudeRows: rows)
        usage.projectPath = projectPath
        usage.canonicalProjectPath = canonicalProjectPath
        return usage
    }
}
