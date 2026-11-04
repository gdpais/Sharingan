import Foundation

/// Claude Code writes the session's working directory (`cwd`) on its transcript lines. The scanner keeps the first
/// one per transcript as the file's `projectPath` and resolves it with the git worktree resolver Codex uses, so
/// Claude usage projects into the same `CostUsageProjectBreakdown` rows as Codex sessions.
extension CostUsageScanner {
    // MARK: - Claude projects

    /// Records the transcript's working directory and its resolved project root on the file usage.
    /// Incremental parses keep the directory first seen in the transcript, like a Codex `session_meta` cwd.
    static func recordClaudeProjectPath(
        into usage: inout CostUsageFileUsage,
        parsedCWD: String?,
        previous: CostUsageFileUsage?,
        resolver: CodexCanonicalProjectPathResolver?)
    {
        guard let projectPath = previous?.projectPath ?? parsedCWD else { return }
        usage.projectPath = projectPath
        if let previous, previous.projectPath == projectPath, let canonical = previous.canonicalProjectPath {
            usage.canonicalProjectPath = canonical
        } else {
            usage.canonicalProjectPath = resolver?.canonicalProjectPath(for: projectPath)
        }
    }

    /// Window-scoped project rows built from the same cache artifact and reconciled winners as the Claude daily
    /// report. Call after the daily scan refreshed the artifact. Other providers, and histories in which no
    /// transcript recorded a working directory, have no project rows.
    static func loadClaudeProjectBreakdowns(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options(),
        reportContext: CostUsageReportContext? = nil,
        checkCancellation: CancellationCheck? = nil) throws -> [CostUsageProjectBreakdown]
    {
        // Provider-specific by design: Claude Code transcripts carry the working directory behind project rows.
        guard provider == .claude else { return [] }
        try checkCancellation?()
        let range = CostUsageDayRange(since: since, until: until, calendar: options.calendar)
        let cacheContext = reportContext ?? .regular
        let cacheURL = CostUsageClaudeCacheIO.cacheFileURL(
            provider: provider,
            cacheRoot: options.cacheRoot,
            reportContext: cacheContext)
        guard let cacheStamp = CostUsageClaudeFileStamp.read(at: cacheURL) else { return [] }
        let key = CostUsageClaudeProjectMemo.Key(
            canonicalCachePath: cacheURL.standardizedFileURL.resolvingSymlinksInPath().path,
            cacheArtifactStamp: cacheStamp,
            pricingArtifactStamp: CostUsageClaudeFileStamp.read(
                at: ModelsDevCache.cacheFileURL(cacheRoot: options.cacheRoot)),
            sinceKey: range.sinceKey,
            untilKey: range.untilKey,
            timeZoneIdentifier: range.calendar.timeZone.identifier)
        let memo = CostUsageClaudeProjectMemo.shared
        if let memoized = memo.projects(for: key) {
            return memoized
        }

        let artifact = CostUsageClaudeCacheIO.load(
            provider: provider,
            cacheRoot: options.cacheRoot,
            reportContext: cacheContext,
            calendar: range.calendar)
        try checkCancellation?()
        let projects = Self.buildClaudeProjectBreakdowns(
            cache: artifact.usage,
            range: range,
            pricingResolver: CostUsagePricing.ClaudeResolver(now: now, cacheRoot: options.cacheRoot))
        try checkCancellation?()
        // Remember only a projection whose artifact did not change while it was read.
        if CostUsageClaudeFileStamp.read(at: cacheURL) == cacheStamp {
            memo.store(projects, for: key)
        }
        return projects
    }

    /// Groups reconciled rows by resolved project root, then by raw working directory as the project's sources.
    /// Each report reuses the daily report's aggregation and pricing, so project rows reconcile with its totals.
    static func buildClaudeProjectBreakdowns(
        cache: CostUsageCache,
        range: CostUsageDayRange,
        pricingResolver: CostUsagePricing.ClaudeResolver) -> [CostUsageProjectBreakdown]
    {
        // Row-less legacy files only carry merged day totals, which cannot be split by project.
        guard !cache.files.isEmpty, cache.files.values.allSatisfy({ $0.claudeRows != nil }) else { return [] }
        var keysByPath: [String: ClaudeProjectKeys] = [:]
        for (path, usage) in cache.files {
            let source = usage.projectPath ?? ""
            keysByPath[path] = ClaudeProjectKeys(project: usage.canonicalProjectPath ?? source, source: source)
        }

        var rowsByProject: [String: [String: [ClaudeUsageRow]]] = [:]
        var hasProjectPath = false
        for winner in Self.reconciledClaudeRowSources(cache: cache) {
            guard CostUsageDayRange.isInRange(
                dayKey: winner.row.dayKey,
                since: range.sinceKey,
                until: range.untilKey)
            else { continue }
            let keys = keysByPath[winner.path] ?? ClaudeProjectKeys(project: "", source: "")
            hasProjectPath = hasProjectPath || !keys.project.isEmpty
            rowsByProject[keys.project, default: [:]][keys.source, default: []].append(winner.row)
        }
        // A history with no recorded working directory stays unattributed instead of one unknown project.
        guard hasProjectPath else { return [] }

        return rowsByProject.compactMap { projectKey, rowsBySource -> CostUsageProjectBreakdown? in
            // Sorted sources keep each projection's summation order stable across refreshes.
            let sourceKeys = rowsBySource.keys.sorted()
            var sourceReports: [(path: String, report: CostUsageDailyReport)] = []
            for sourceKey in sourceKeys {
                let report = Self.buildClaudeReportFromCache(
                    cache: cache,
                    rows: rowsBySource[sourceKey] ?? [],
                    range: range,
                    pricingResolver: pricingResolver)
                if !report.data.isEmpty {
                    sourceReports.append((path: sourceKey, report: report))
                }
            }
            guard let firstSource = sourceReports.first else { return nil }
            let report = sourceReports.count == 1
                ? firstSource.report
                : Self.buildClaudeReportFromCache(
                    cache: cache,
                    rows: sourceKeys.flatMap { rowsBySource[$0] ?? [] },
                    range: range,
                    pricingResolver: pricingResolver)
            let projectPath = projectKey.isEmpty ? nil : projectKey
            return CostUsageProjectBreakdown(
                name: Self.claudeProjectName(path: projectPath),
                path: projectPath,
                totalTokens: report.summary?.totalTokens,
                totalCostUSD: report.summary?.totalCostUSD,
                daily: report.data,
                modelBreakdowns: Self.claudeProjectModelBreakdowns(from: report.data),
                sources: Self.claudeProjectSourceBreakdowns(sourceReports))
        }
        .sorted { lhs, rhs in
            let lhsRank = (lhs.totalCostUSD ?? -1, lhs.totalTokens ?? -1)
            let rhsRank = (rhs.totalCostUSD ?? -1, rhs.totalTokens ?? -1)
            if lhsRank != rhsRank {
                return lhsRank > rhsRank
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return (lhs.path ?? "") < (rhs.path ?? "")
        }
    }

    private struct ClaudeProjectKeys {
        let project: String
        let source: String
    }

    private static func claudeProjectSourceBreakdowns(
        _ sourceReports: [(path: String, report: CostUsageDailyReport)]) -> [CostUsageProjectSourceBreakdown]
    {
        sourceReports.map { source in
            let sourcePath = source.path.isEmpty ? nil : source.path
            return CostUsageProjectSourceBreakdown(
                name: Self.claudeProjectName(path: sourcePath),
                path: sourcePath,
                totalTokens: source.report.summary?.totalTokens,
                totalCostUSD: source.report.summary?.totalCostUSD,
                daily: source.report.data,
                modelBreakdowns: Self.claudeProjectModelBreakdowns(from: source.report.data))
        }
        .sorted { lhs, rhs in
            let lhsRank = (lhs.totalCostUSD ?? -1, lhs.totalTokens ?? -1)
            let rhsRank = (rhs.totalCostUSD ?? -1, rhs.totalTokens ?? -1)
            if lhsRank != rhsRank {
                return lhsRank > rhsRank
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func claudeProjectName(path: String?) -> String {
        guard let path, !path.isEmpty else { return CostUsageProjectBreakdown.unknownProjectName }
        let name = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return name.isEmpty ? path : name
    }

    private static func claudeProjectModelBreakdowns(
        from entries: [CostUsageDailyReport.Entry]) -> [CostUsageDailyReport.ModelBreakdown]?
    {
        let summaries = CostUsageDailyReport.modelCostSummaries(from: entries)
        return summaries.isEmpty ? nil : Self.sortedModelBreakdowns(summaries)
    }
}

/// In-process memo so refreshes of an unchanged Claude cache artifact do not reprice every retained row again.
final class CostUsageClaudeProjectMemo: @unchecked Sendable {
    struct Key: Equatable {
        let canonicalCachePath: String
        let cacheArtifactStamp: CostUsageClaudeFileStamp
        let pricingArtifactStamp: CostUsageClaudeFileStamp?
        let sinceKey: String
        let untilKey: String
        let timeZoneIdentifier: String

        func sameWindow(as other: Self) -> Bool {
            self.canonicalCachePath == other.canonicalCachePath
                && self.sinceKey == other.sinceKey
                && self.untilKey == other.untilKey
                && self.timeZoneIdentifier == other.timeZoneIdentifier
        }
    }

    static let shared = CostUsageClaudeProjectMemo()

    private let lock = NSLock()
    private let capacity = 4
    private var entries: [(key: Key, projects: [CostUsageProjectBreakdown])] = []

    func projects(for key: Key) -> [CostUsageProjectBreakdown]? {
        self.lock.withLock { self.entries.first(where: { $0.key == key })?.projects }
    }

    func store(_ projects: [CostUsageProjectBreakdown], for key: Key) {
        self.lock.withLock {
            self.entries.removeAll { $0.key.sameWindow(as: key) }
            self.entries.append((key: key, projects: projects))
            if self.entries.count > self.capacity { self.entries.removeFirst() }
        }
    }
}
