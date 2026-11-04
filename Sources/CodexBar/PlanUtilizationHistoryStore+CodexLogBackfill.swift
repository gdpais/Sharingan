import CodexBarCore
import Foundation

// MARK: - Codex log backfill

extension PlanUtilizationHistoryStore {
    /// Series that Codex rollout samples may backfill: the 5-hour session and the weekly window.
    private static let codexLogBackfillSeries: [(name: PlanUtilizationSeriesName, windowMinutes: Int)] = [
        (.session, 5 * 60),
        (.weekly, 7 * 24 * 60),
    ]

    /// Folds Codex rollout `rate_limits` samples into the hourly-peak session (300 min) and weekly (10080 min)
    /// series of one account's history.
    ///
    /// Only hours that have no recorded entry in that series are filled, so live samples always win, recorded entries
    /// are never changed, and a repeated run over the same logs changes nothing. Samples older than `horizon` are
    /// ignored, and a series never grows past `UsageStore.planUtilizationMaxSamples` (the oldest backfilled hours are
    /// dropped first; recorded entries are never evicted to make room). Returns nil when nothing changes.
    static func codexHistoriesBackfillingLogSamples(
        _ samples: [CodexRateLimitLogSample],
        into histories: [PlanUtilizationSeriesHistory],
        notBefore horizon: Date) -> [PlanUtilizationSeriesHistory]?
    {
        var updatedHistories = histories
        var didChange = false

        for series in self.codexLogBackfillSeries {
            let incoming = self.codexLogBackfillEntries(
                samples,
                name: series.name,
                windowMinutes: series.windowMinutes,
                notBefore: horizon)
            guard !incoming.isEmpty else { continue }

            // Near-canonical legacy series (e.g. 299 minutes) still count as recorded hours.
            let matchingHistories = updatedHistories.filter {
                $0.name == series.name && $0.name.canonicalWindowMinutes($0.windowMinutes) == series.windowMinutes
            }
            let recordedHours = Set(matchingHistories.flatMap(\.entries).map {
                self.codexLogBackfillHourBucket(for: $0.capturedAt)
            })

            var foldedEntries: [PlanUtilizationHistoryEntry] = []
            for entry in incoming {
                guard !recordedHours.contains(self.codexLogBackfillHourBucket(for: entry.capturedAt)) else { continue }
                // Same hourly peak folding (including reset-boundary splits) as live samples.
                _ = UsageStore.updatedPlanUtilizationEntries(existingEntries: &foldedEntries, entry: entry)
            }
            guard !foldedEntries.isEmpty else { continue }

            let targetIndex = updatedHistories.firstIndex {
                $0.name == series.name && $0.windowMinutes == series.windowMinutes
            }
            let recordedEntries = targetIndex.map { updatedHistories[$0].entries } ?? []
            let room = UsageStore.planUtilizationMaxSamples - recordedEntries.count
            guard room > 0 else { continue }

            let mergedHistory = PlanUtilizationSeriesHistory(
                name: series.name,
                windowMinutes: series.windowMinutes,
                entries: recordedEntries + Array(foldedEntries.suffix(room)))
            if let targetIndex {
                updatedHistories[targetIndex] = mergedHistory
            } else {
                updatedHistories.append(mergedHistory)
            }
            didChange = true
        }

        guard didChange else { return nil }
        return updatedHistories.sorted(by: PlanUtilizationSeriesHistory.precedes)
    }

    private static func codexLogBackfillEntries(
        _ samples: [CodexRateLimitLogSample],
        name: PlanUtilizationSeriesName,
        windowMinutes: Int,
        notBefore horizon: Date) -> [PlanUtilizationHistoryEntry]
    {
        var entries: [PlanUtilizationHistoryEntry] = []
        for sample in samples where sample.observedAt >= horizon {
            for window in sample.windows {
                // Live history also skips windows without an advertised length.
                guard let sampleWindowMinutes = window.windowMinutes,
                      name.canonicalWindowMinutes(sampleWindowMinutes) == windowMinutes
                else { continue }
                entries.append(PlanUtilizationHistoryEntry(
                    capturedAt: sample.observedAt,
                    usedPercent: max(0, min(100, window.usedPercent)),
                    resetsAt: window.resetsAt))
            }
        }
        return entries.sorted { $0.capturedAt < $1.capturedAt }
    }

    /// Same bucket as live recording (`UsageStore.planUtilizationHourBucket`): one per UTC clock hour.
    private static func codexLogBackfillHourBucket(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / 3600))
    }
}
