import Foundation

/// The window before the History window, for "+12% vs previous 30 days" on the cost history chart.
///
/// Claude transcripts keep a window-scoped cache, so the daily scan widens only its scan window to
/// cover both periods and keeps reporting the History window exactly as before; the previous period
/// is then read from that cache without another scan. Codex keeps a store whose coverage is checked
/// per range, so its previous period is read only when the store already covers both windows.
extension CostUsageScanner {
    /// The History window's daily report, with the cache retaining the scan window from `retainSince`.
    /// Without `retainSince`, and for providers without a window-scoped transcript cache, this reports
    /// exactly as `loadDailyReportCancellable`.
    static func loadDailyReportRetainingPreviousPeriod(
        provider: UsageProvider,
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options(),
        reportContext: CostUsageReportContext?,
        retainSince: Date? = nil,
        checkCancellation: CancellationCheck?) throws -> CostUsageDailyReport
    {
        // Provider-specific by design: only the Claude/Vertex transcript cache can retain a wider scan window.
        guard let retainSince, provider == .claude || provider == .vertexai else {
            return try self.loadDailyReportCancellable(
                provider: provider,
                since: since,
                until: until,
                now: now,
                options: options,
                reportContext: reportContext,
                checkCancellation: checkCancellation)
        }
        try checkCancellation?()
        var filtered = options
        if provider == .vertexai, filtered.claudeLogProviderFilter == .all {
            filtered.claudeLogProviderFilter = .vertexAIOnly
        }
        let range = CostUsageDayRange(since: since, until: until, calendar: options.calendar)
        let retained = CostUsageDayRange(since: retainSince, until: until, calendar: options.calendar)
        return try self.loadClaudeDaily(
            provider: provider,
            range: range.retainingScanWindow(since: retained.scanSinceKey, until: range.scanUntilKey),
            now: now,
            options: filtered,
            reportContext: reportContext,
            checkCancellation: checkCancellation)
    }

    /// The previous window's daily report, read from the cache that `loadDailyReportRetainingPreviousPeriod`
    /// just refreshed. Nil when the cache does not span the whole window, or when the transcripts that
    /// would hold it may be gone: Claude Code deletes transcripts after 30 days by default, so the
    /// window counts as covered only when a retained transcript was last written before it began.
    static func loadClaudePreviousPeriodReport(
        provider: UsageProvider,
        request: CostUsagePreviousPeriodRequest,
        options: Options,
        reportContext: CostUsageReportContext?) -> CostUsageDailyReport?
    {
        // Provider-specific by design: only the Claude/Vertex transcript cache retains the previous window.
        guard provider == .claude || provider == .vertexai else { return nil }
        let range = request.range(calendar: options.calendar)
        let artifact = CostUsageClaudeCacheIO.load(
            provider: provider,
            cacheRoot: options.cacheRoot,
            reportContext: reportContext ?? .regular,
            calendar: range.calendar)
        let cache = artifact.usage
        guard let cachedSince = cache.scanSinceKey,
              cachedSince <= range.sinceKey,
              CostUsagePreviousPeriod.transcriptsCover(
                  sinceKey: range.sinceKey,
                  oldestTranscriptWriteUnixMs: cache.files.values.map(\.mtimeUnixMs).min(),
                  calendar: range.calendar)
        else { return nil }
        return Self.buildClaudeReportFromCache(
            cache: cache,
            rows: Self.reconciledClaudeRows(cache: cache),
            range: range,
            pricingResolver: CostUsagePricing.ClaudeResolver(now: request.now, cacheRoot: options.cacheRoot))
    }
}
