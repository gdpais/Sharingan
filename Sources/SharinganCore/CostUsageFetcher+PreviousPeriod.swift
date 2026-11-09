import Foundation

/// Reading the equal window before the History window, so the cost history can compare against it.
///
/// The previous window is read only for rolling windows of a week up to a quarter: shorter windows
/// compare a partial today against whole days, and longer ones would double a large scan for a
/// comparison Claude's default 30-day transcript cleanup rarely leaves data for. The Usage & Spend
/// window keeps its own wide cache and never asks for it.
struct CostUsagePreviousPeriodRequest: Equatable, Sendable {
    /// Windows longer than this read no previous period.
    static let maximumDays = 92

    /// First local day of the previous window, which is also where the retained scan window starts.
    let since: Date
    /// Last local day of the previous window: the day before the History window starts.
    let until: Date
    let now: Date

    /// Nil when this read compares nothing. `since` is the History window's first day, as scanned.
    init?(
        historyDays: Int,
        since currentSince: Date,
        now: Date,
        calendar: Calendar,
        reportContext: CostUsageReportContext?)
    {
        guard reportContext != .spendDashboard,
              historyDays >= CostHistoryModelStack.minimumDeltaDays,
              historyDays <= Self.maximumDays,
              let since = calendar.date(byAdding: .day, value: -historyDays, to: currentSince),
              let until = calendar.date(byAdding: .day, value: -1, to: currentSince)
        else { return nil }
        self.since = since
        self.until = until
        self.now = now
    }

    func range(calendar: Calendar) -> CostUsageScanner.CostUsageDayRange {
        CostUsageScanner.CostUsageDayRange(since: self.since, until: self.until, calendar: calendar)
    }
}

enum CostUsagePreviousPeriod {
    /// Whether transcripts cover a window that starts on `sinceKey`. Cleanup deletes transcripts by their
    /// last write, so a retained transcript last written before that day puts any cleanup cutoff before
    /// the window; without one, older transcripts may be gone and the window reads as uncovered.
    static func transcriptsCover(sinceKey: String, oldestTranscriptWriteUnixMs: Int64?, calendar: Calendar) -> Bool {
        guard let oldest = oldestTranscriptWriteUnixMs, oldest > 0 else { return false }
        let written = Date(timeIntervalSince1970: Double(oldest) / 1000)
        return CostUsageLocalDay.key(from: written, calendar: calendar) < sinceKey
    }
}

extension CostUsageFetcher {
    /// The previous window from the Codex store, only when the store already covers it and the History
    /// window together; this read never scans. Nil otherwise.
    static func codexPreviousPeriodDaily(
        view: CostUsageStoreReadView,
        request: CostUsagePreviousPeriodRequest,
        options: CostUsageScanner.Options,
        rootsFingerprint: [String: Int64]) -> [CostUsageDailyReport.Entry]?
    {
        let both = CostUsageScanner.CostUsageDayRange(
            since: request.since,
            until: request.now,
            calendar: options.calendar)
        guard view.historyCoverageIsEstablished(range: both, rootsFingerprint: rootsFingerprint) else { return nil }
        return view.dailyReport(range: request.range(calendar: options.calendar), cacheRoot: options.cacheRoot).data
    }

    /// The previous window from the Claude/Vertex transcript cache; nil for other providers or when uncovered.
    static func claudePreviousPeriodDaily(
        provider: UsageProvider,
        request: CostUsagePreviousPeriodRequest?,
        options: CostUsageScanner.Options,
        reportContext: CostUsageReportContext?) -> [CostUsageDailyReport.Entry]?
    {
        guard let request else { return nil }
        return CostUsageScanner.loadClaudePreviousPeriodReport(
            provider: provider,
            request: request,
            options: options,
            reportContext: reportContext)?.data
    }
}
