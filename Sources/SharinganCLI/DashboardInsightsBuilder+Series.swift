import Foundation
import SharinganCore

// MARK: - Cost by model

extension DashboardInsightsBuilder {
    /// Each provider's daily spend stacked by its own top models. Providers stay separate, so no chart mixes one
    /// provider's models into another's bars.
    static func costByModel(
        _ sources: [Source],
        range: ClosedRange<Date>,
        calendar: Calendar) -> [DashboardCostByModelPayload]
    {
        sources.compactMap { source -> DashboardCostByModelPayload? in
            let window = source.entries(in: range)
            let models = CostHistoryModelStack.topModels(
                window.map(\.entry),
                metric: .cost,
                limit: self.costByModelTopCount)
            guard !models.isEmpty else { return nil }
            let days = window.compactMap { item -> DashboardCostByModelDayPayload? in
                guard let total = self.validCost(item.entry.costUSD) else { return nil }
                let segments = CostHistoryModelStack.segments(
                    for: item.entry,
                    total: total,
                    topModels: models,
                    metric: .cost)
                return DashboardCostByModelDayPayload(
                    date: self.dayKey(item.day, calendar: calendar),
                    total: total,
                    segments: segments.map { self.segmentPayload($0) })
            }
            guard days.contains(where: { $0.total > 0 }) else { return nil }
            return DashboardCostByModelPayload(
                provider: source.sourceID,
                providerName: source.name,
                models: models,
                hasOther: days.contains { day in day.segments.contains(where: \.isOther) },
                days: days)
        }
    }

    private static func segmentPayload(_ segment: CostHistoryModelStack.Segment) -> DashboardCostByModelSegmentPayload {
        switch segment.series {
        case let .model(rank):
            DashboardCostByModelSegmentPayload(rank: rank, isOther: false, value: segment.end - segment.start)
        case .other:
            DashboardCostByModelSegmentPayload(rank: nil, isOther: true, value: segment.end - segment.start)
        }
    }
}

// MARK: - Model share

extension DashboardInsightsBuilder {
    /// Each model's share of priced spend per bucket, across every source; smaller models fold into Other.
    static func modelShare(
        _ sources: [Source],
        range: ClosedRange<Date>,
        bucket: SpendInsightBucket,
        calendar: Calendar) -> DashboardModelSharePayload?
    {
        var observations: [SpendShareOverTime.Observation] = []
        var modelNames: [String: String] = [:]
        var providers: [String: Source] = [:]
        for source in sources {
            for item in source.entries(in: range) {
                for breakdown in item.entry.modelBreakdowns ?? [] {
                    let name = CostHistoryModelStack.seriesName(breakdown.modelName)
                    guard !name.isEmpty, let cost = self.validCost(breakdown.costUSD), cost > 0 else { continue }
                    let id = "\(source.sourceID):\(name)"
                    observations.append(SpendShareOverTime.Observation(day: item.day, seriesID: id, value: cost))
                    modelNames[id] = name
                    providers[id] = source
                }
            }
        }
        guard !observations.isEmpty else { return nil }
        let share = SpendShareOverTime(
            observations: observations,
            topCount: self.modelShareTopCount,
            bucket: bucket,
            calendar: calendar)
        guard !share.isEmpty else { return nil }

        // A model name reported by two providers carries its provider so the legend stays unambiguous.
        var nameCounts: [String: Int] = [:]
        for name in modelNames.values {
            nameCounts[name, default: 0] += 1
        }
        let series = share.series.map { entry -> DashboardModelShareSeriesPayload in
            let name = modelNames[entry.id] ?? entry.id
            let providerName = providers[entry.id]?.name
            let label = (nameCounts[name] ?? 0) > 1 ? providerName.map { "\(name) · \($0)" } ?? name : name
            return DashboardModelShareSeriesPayload(
                id: entry.isOther ? "other" : entry.id,
                name: entry.isOther ? "Other" : label,
                provider: entry.isOther ? nil : providers[entry.id]?.sourceID,
                rank: entry.rank,
                total: entry.total,
                share: entry.share,
                isOther: entry.isOther,
                foldedCount: entry.foldedSeriesIDs.count)
        }
        let points = share.points.map { point in
            DashboardModelSharePointPayload(
                date: self.dayKey(point.bucketStart, calendar: calendar),
                series: point.seriesID == SpendShareOverTime.otherSeriesID ? "other" : point.seriesID,
                value: point.value,
                share: point.share,
                shareStart: point.shareStart,
                shareEnd: point.shareEnd)
        }
        return DashboardModelSharePayload(
            bucket: share.bucket.rawValue,
            total: share.total,
            series: series,
            points: points)
    }
}

// MARK: - Project trends

extension DashboardInsightsBuilder {
    private struct ProjectIdentity {
        let source: Source
        let name: String
        let path: String?
        let isProjectless: Bool
    }

    private struct ProjectTrendInput {
        var observations: [SpendSeriesTrends.Observation] = []
        var identities: [String: ProjectIdentity] = [:]
        var coverage: [String: ClosedRange<Date>] = [:]
        var days: ClosedRange<Date>?
    }

    /// The top projects' spend over the range, each with the change between the range's two halves. Names and
    /// paths appear only with full identity; otherwise each project is a numbered placeholder.
    static func projectTrends(
        _ sources: [Source],
        range: ClosedRange<Date>,
        identityMode: DashboardIdentityMode,
        calendar: Calendar) -> DashboardProjectTrendsPayload?
    {
        let input = self.projectTrendInput(sources, range: range, calendar: calendar)
        guard let days = input.days, !input.observations.isEmpty else { return nil }
        let bucket = self.bucket(for: days, calendar: calendar)
        let trends = SpendSeriesTrends(
            observations: input.observations,
            days: days,
            bucket: bucket,
            topCount: self.projectTrendTopCount,
            calendar: calendar,
            coverage: input.coverage)
        guard !trends.trends.isEmpty else { return nil }

        let showsIdentity = identityMode == .full
        let projects = trends.trends.compactMap { trend -> DashboardProjectTrendPayload? in
            guard let identity = input.identities[trend.id] else { return nil }
            let change = self.changeFields(trend.change)
            return DashboardProjectTrendPayload(
                rank: trend.rank,
                label: showsIdentity ? identity.name : "Project \(trend.rank)",
                path: showsIdentity ? identity.path : nil,
                provider: identity.source.sourceID,
                providerName: identity.source.name,
                total: trend.total,
                recentTotal: trend.recentTotal,
                previousTotal: trend.previousTotal,
                change: change.kind,
                changeFraction: change.fraction,
                points: trend.points.map { point in
                    DashboardTrendPointPayload(
                        date: self.dayKey(point.bucketStart, calendar: calendar),
                        value: point.value)
                })
        }
        guard !projects.isEmpty else { return nil }
        return DashboardProjectTrendsPayload(
            bucket: bucket.rawValue,
            start: self.dayKey(days.lowerBound, calendar: calendar),
            end: self.dayKey(days.upperBound, calendar: calendar),
            comparisonDays: trends.comparisonDayCount,
            omittedCount: trends.omittedSeriesCount,
            maxValue: trends.maximumPointValue,
            projects: projects)
    }

    /// Per provider and project identity, only days inside the range and the source's coverage count, and an
    /// identity is an independent chat only when every record agrees. Independent chats are not projects.
    private static func projectTrendInput(
        _ sources: [Source],
        range: ClosedRange<Date>,
        calendar: Calendar) -> ProjectTrendInput
    {
        var result = ProjectTrendInput()
        var observations: [SpendSeriesTrends.Observation] = []
        var firstDay: Date?
        var lastDay: Date?
        for source in sources {
            guard !source.input.projects.isEmpty, let covered = self.clip(source.coverage, to: range) else { continue }
            firstDay = min(firstDay ?? covered.lowerBound, covered.lowerBound)
            lastDay = max(lastDay ?? covered.upperBound, covered.upperBound)
            for project in source.input.projects {
                let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let id = "\(source.sourceID):\(project.path.map { "path:\($0)" } ?? "name:\(name)")"
                result.coverage[id] = covered
                let existing = result.identities[id]
                let keepsExistingName = existing.map { !$0.isProjectless || project.isProjectless } ?? false
                result.identities[id] = ProjectIdentity(
                    source: source,
                    name: keepsExistingName ? (existing?.name ?? name) : name,
                    path: project.path,
                    isProjectless: (existing?.isProjectless ?? true) && project.isProjectless)
                for entry in project.daily {
                    guard let day = self.day(entry.date, calendar: calendar),
                          covered.contains(day),
                          let cost = self.validCost(entry.costUSD),
                          cost > 0
                    else { continue }
                    observations.append(SpendSeriesTrends.Observation(seriesID: id, day: day, value: cost))
                }
            }
        }
        let identities = result.identities
        result.observations = observations.filter { identities[$0.seriesID]?.isProjectless == false }
        if let firstDay, let lastDay, firstDay <= lastDay {
            result.days = firstDay...lastDay
        }
        return result
    }

    private static func changeFields(_ change: CodexModelsComparison) -> (kind: String, fraction: Double?) {
        switch change {
        case .unavailable:
            ("unavailable", nil)
        case .new:
            ("new", nil)
        case .ended:
            ("ended", nil)
        case .unchanged:
            ("unchanged", 0)
        case let .percent(value):
            ("percent", value.isFinite ? value : nil)
        }
    }
}
