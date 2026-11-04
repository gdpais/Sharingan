import CodexBarCore
import Foundation

/// Series for the Usage & Spend insight panels, built once with each currency group.
struct SpendDashboardInsights: Equatable, Sendable {
    static let modelShareTopCount = 5
    static let projectTrendTopCount = 5

    /// Each model's share of priced spend per bucket of the range; smaller models fold into Other.
    var modelShare: SpendShareOverTime?
    /// Legend names for model share series, keyed by series ID.
    var modelNames: [String: String] = [:]
    /// The top projects' spend over the range, each with the change between the range's two halves.
    var projectTrends: SpendSeriesTrends?
    /// The ledger identity of each trend, keyed by `ProjectRow.id`, so labels redact like the Projects list.
    var projectIdentities: [String: SpendDashboardModel.ProjectRow] = [:]
}

extension SpendDashboardModel {
    private struct ModelShareInput {
        var observations: [SpendShareOverTime.Observation] = []
        var names: [String: String] = [:]
    }

    private struct ProjectTrendInput {
        var observations: [SpendSeriesTrends.Observation] = []
        var identities: [String: ProjectRow] = [:]
        var days: ClosedRange<Date>?
    }

    /// Model share follows the aggregate sources like the Models list; project trends follow the detail
    /// sources and per-project daily rows like the Projects list. Both ignore a selected day: they show the range.
    static func insights(
        summaries: [InputSummary],
        detailSummaries: [InputSummary],
        bounds: ClosedRange<Date>,
        detailBounds: ClosedRange<Date>,
        calendar: Calendar) -> SpendDashboardInsights
    {
        var insights = SpendDashboardInsights()

        let models = Self.modelShareInput(summaries: summaries)
        if !models.observations.isEmpty {
            insights.modelShare = SpendShareOverTime(
                observations: models.observations,
                topCount: SpendDashboardInsights.modelShareTopCount,
                bucket: Self.insightBucket(for: bounds, calendar: calendar),
                calendar: calendar)
            insights.modelNames = models.names
        }

        let projects = Self.projectTrendInput(summaries: detailSummaries, bounds: detailBounds, calendar: calendar)
        if let days = projects.days, !projects.observations.isEmpty {
            let trends = SpendSeriesTrends(
                observations: projects.observations,
                days: days,
                bucket: Self.insightBucket(for: days, calendar: calendar),
                topCount: SpendDashboardInsights.projectTrendTopCount,
                calendar: calendar)
            insights.projectTrends = trends
            for trend in trends.trends {
                insights.projectIdentities[trend.id] = projects.identities[trend.id]
            }
        }
        return insights
    }

    /// The same day, week or month grouping the spend trend chart uses for a range of this length.
    static func insightBucket(for days: ClosedRange<Date>, calendar: Calendar) -> SpendInsightBucket {
        let lastDay = calendar.startOfDay(for: days.upperBound)
        let end = max(days.lowerBound, calendar.date(byAdding: .day, value: 1, to: lastDay) ?? days.upperBound)
        let unit = SpendTrendChartModel.overviewUnit(in: days.lowerBound...end, calendar: calendar)
        return switch unit {
        case .month: .month
        case .weekOfYear: .week
        default: .day
        }
    }

    private static func modelShareInput(summaries: [InputSummary]) -> ModelShareInput {
        var input = ModelShareInput()
        var modelNames: [String: String] = [:]
        var providerNames: [String: String] = [:]
        for summary in summaries {
            for windowEntry in summary.entries {
                for breakdown in windowEntry.entry.modelBreakdowns ?? [] {
                    let name = breakdown.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty,
                          let cost = Self.validCost(breakdown.costUSD).map({ $0 * summary.costMultiplier }),
                          cost.isFinite,
                          cost > 0
                    else { continue }
                    // Same key as `ModelRow.id`, so one model is one series across sources of a provider.
                    let id = "\(summary.input.provider.rawValue):\(name)"
                    input.observations.append(SpendShareOverTime.Observation(
                        day: windowEntry.day,
                        seriesID: id,
                        value: cost))
                    modelNames[id] = name
                    providerNames[id] = summary.input.modelProviderName
                }
            }
        }
        // A model name reported by two providers carries its provider so the legend stays unambiguous.
        var nameCounts: [String: Int] = [:]
        for name in modelNames.values {
            nameCounts[name, default: 0] += 1
        }
        for (id, name) in modelNames {
            let providerName = providerNames[id] ?? ""
            let isAmbiguous = (nameCounts[name] ?? 0) > 1 && !providerName.isEmpty
            input.names[id] = isAmbiguous ? "\(name) · \(providerName)" : name
        }
        return input
    }

    /// Mirrors `projectRows`: per source and project identity, only days inside the range and the source's
    /// covered interval count, and an identity is an independent chat only when every record agrees.
    private static func projectTrendInput(
        summaries: [InputSummary],
        bounds: ClosedRange<Date>,
        calendar: Calendar) -> ProjectTrendInput
    {
        var result = ProjectTrendInput()
        var observations: [SpendSeriesTrends.Observation] = []
        var firstCoveredDay: Date?
        var lastCoveredDay: Date?
        for summary in summaries {
            let input = summary.input
            guard !input.snapshot.projects.isEmpty, let covered = summary.coveredInterval else { continue }
            firstCoveredDay = min(firstCoveredDay ?? covered.lowerBound, covered.lowerBound)
            lastCoveredDay = max(lastCoveredDay ?? covered.upperBound, covered.upperBound)
            for project in input.snapshot.projects {
                let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let id = "\(input.id):\(project.path.map { "path:\($0)" } ?? "name:\(name)")"
                let existing = result.identities[id]
                let keepsExistingName = existing.map { !$0.isProjectless || project.isProjectless } ?? false
                result.identities[id] = ProjectRow(
                    rank: 0,
                    provider: input.provider,
                    providerName: input.modelProviderName,
                    sourceID: input.id,
                    projectName: keepsExistingName ? (existing?.projectName ?? name) : name,
                    path: project.path,
                    totalTokens: nil,
                    totalCost: nil,
                    isProjectless: (existing?.isProjectless ?? true) && project.isProjectless)
                for entry in project.daily {
                    guard let day = Self.day(entry.date, provider: input.provider, displayCalendar: calendar),
                          bounds.contains(day),
                          covered.contains(day),
                          let cost = Self.validCost(entry.costUSD).map({ $0 * summary.costMultiplier }),
                          cost.isFinite,
                          cost > 0
                    else { continue }
                    observations.append(SpendSeriesTrends.Observation(seriesID: id, day: day, value: cost))
                }
            }
        }
        // Independent chats have their own list; trends cover projects only.
        let identities = result.identities
        result.observations = observations.filter { identities[$0.seriesID]?.isProjectless == false }
        if let firstCoveredDay, let lastCoveredDay, firstCoveredDay <= lastCoveredDay {
            result.days = firstCoveredDay...lastCoveredDay
        }
        return result
    }
}
