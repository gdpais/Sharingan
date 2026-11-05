import CodexBarCore
import Foundation

/// Feeds the insight tiles from the dashboard's own window summaries, so the tiles share its day
/// bucketing, currency conversion and coverage rules instead of re-reading snapshots.
extension SpendDashboardModel {
    typealias InsightSummarizer = (ProviderInput, Double, ClosedRange<Date>, Calendar) -> InputSummary

    /// The selected range's per-source days, plus the equal-length period just before it when every
    /// source's history covers that whole period. `summarize` is the dashboard's window summary
    /// builder, so the earlier period follows the same validity rules as the range itself.
    static func insightInputs(
        _ summaries: [InputSummary],
        _ bounds: ClosedRange<Date>,
        _ calendar: Calendar,
        _ summarize: InsightSummarizer) -> SpendInsightInputs
    {
        let dayCount = Self.dayCount(in: bounds, calendar: calendar)
        guard dayCount > 0, !summaries.isEmpty else { return SpendInsightInputs() }
        return SpendInsightInputs(
            period: SpendInsightPeriod(start: bounds.lowerBound, dayCount: dayCount),
            samples: summaries.flatMap { Self.insightSamples($0) },
            previousSamples: Self.previousInsightSamples(
                summaries,
                bounds: bounds,
                dayCount: dayCount,
                calendar: calendar,
                summarize: summarize),
            coverage: Self.insightCoverage(summaries))
    }

    /// Days each source's history covers inside the range, so plan value prorates a plan price over
    /// covered days only.
    static func insightCoverage(_ summaries: [InputSummary]) -> [String: ClosedRange<Date>] {
        var coverage: [String: ClosedRange<Date>] = [:]
        for summary in summaries {
            guard let interval = summary.coveredInterval else { continue }
            coverage[summary.input.id] = interval
        }
        return coverage
    }

    static func insightSamples(_ summary: InputSummary) -> [SpendInsightSample] {
        summary.entries.map { windowEntry -> SpendInsightSample in
            let entry = windowEntry.entry
            let cost = summary.hasInvalidCostHistory
                ? nil
                : Self.validCost(entry.costUSD).map { $0 * summary.costMultiplier }
            return SpendInsightSample(
                sourceID: summary.input.id,
                day: windowEntry.day,
                cost: cost,
                totalTokens: entry.hasOnlyIncompleteRequests ? nil : entry.totalTokens,
                inputTokens: entry.inputTokens,
                cacheReadTokens: entry.cacheReadTokens,
                cacheCreationTokens: entry.cacheCreationTokens,
                outputTokens: entry.outputTokens,
                reasoningTokens: entry.reasoningTokens,
                modelCosts: cost == nil ? [] : Self.insightModelCosts(entry, summary: summary),
                costCoversTokens: Self.insightCostCoversTokens(entry))
        }
    }

    /// Unpriced, unmetered or incomplete requests keep their tokens but add no spend, so the day's
    /// cost would understate cost per 1M tokens.
    private static func insightCostCoversTokens(_ entry: CostUsageDailyReport.Entry) -> Bool {
        guard entry.coverageCounts.unpriced == 0,
              entry.coverageCounts.unmetered == 0,
              entry.incompleteRequestCount == 0
        else { return false }
        return !(entry.modelBreakdowns ?? []).contains { breakdown in
            Self.validCost(breakdown.costUSD) == nil && (breakdown.totalTokens ?? 0) > 0
        }
    }

    private static func previousInsightSamples(
        _ summaries: [InputSummary],
        bounds: ClosedRange<Date>,
        dayCount: Int,
        calendar: Calendar,
        summarize: InsightSummarizer) -> [SpendInsightSample]?
    {
        guard let start = calendar.date(byAdding: .day, value: -dayCount, to: bounds.lowerBound),
              let end = calendar.date(byAdding: .day, value: -1, to: bounds.lowerBound)
        else { return nil }
        let previousBounds = calendar.startOfDay(for: start)...calendar.startOfDay(for: end)
        let previous = summaries.map { summarize($0.input, $0.costMultiplier, previousBounds, calendar) }
        // A source whose history starts inside the earlier period would turn the comparison into a
        // floor, so the delta is offered only when every source covers all of it.
        guard previous.allSatisfy({ $0.coveredInterval == previousBounds }) else { return nil }
        return previous.flatMap { Self.insightSamples($0) }
    }

    private static func insightModelCosts(
        _ entry: CostUsageDailyReport.Entry,
        summary: InputSummary) -> [SpendInsightSample.ModelCost]
    {
        (entry.modelBreakdowns ?? []).compactMap { breakdown -> SpendInsightSample.ModelCost? in
            let name = breakdown.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let cost = Self.validCost(breakdown.costUSD) else { return nil }
            return SpendInsightSample.ModelCost(
                id: "\(summary.input.provider.rawValue):\(name)",
                name: name,
                cost: cost * summary.costMultiplier)
        }
    }
}
