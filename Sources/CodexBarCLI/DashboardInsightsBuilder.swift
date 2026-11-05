import CodexBarCore
import Foundation

/// Builds the snapshot's `insights` block from the cost payloads the dashboard already collected, using the Core
/// insight models the Usage & Spend window uses. Only USD sources take part, over the last `rangeDays` local days.
///
/// Plan fit is not part of the block: its plan-utilization history store lives in the macOS app, not in Core.
enum DashboardInsightsBuilder {
    static let rangeDays = 30
    static let costByModelTopCount = 5
    static let modelShareTopCount = 5
    static let projectTrendTopCount = 5

    /// One daily entry on its local day.
    struct DayEntry {
        let day: Date
        let entry: CostUsageDailyReport.Entry
    }

    /// One provider's scan: the days it covers and its daily entries inside them.
    struct Source {
        let input: DashboardCostInsightSource
        let name: String
        /// Local days the scan covers, from its first day through its last.
        let coverage: ClosedRange<Date>
        /// Entries on covered days, oldest first.
        let days: [DayEntry]

        var sourceID: String {
            self.input.provider.rawValue
        }

        func entries(in bounds: ClosedRange<Date>) -> [DayEntry] {
            self.days.filter { bounds.contains($0.day) }
        }
    }

    /// Gregorian days in the host time zone, matching the dashboard's cost day keys, with the host's first weekday.
    static func defaultCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    /// `nil` when no USD source reports anything an insight can show.
    static func makeInsights(
        costPayloads: [CostPayload],
        identityMode: DashboardIdentityMode,
        generatedAt: Date,
        calendar: Calendar = DashboardInsightsBuilder.defaultCalendar(),
        planMonthlyPrice: Double? = nil) -> DashboardInsightsPayload?
    {
        let end = calendar.startOfDay(for: generatedAt)
        guard let first = calendar.date(byAdding: .day, value: -(self.rangeDays - 1), to: end) else { return nil }
        let range = calendar.startOfDay(for: first)...end
        let sources = self.sources(costPayloads, calendar: calendar)
        guard !sources.isEmpty else { return nil }

        let bucket = self.bucket(for: range, calendar: calendar)
        let costByModel = self.costByModel(sources, range: range, calendar: calendar)
        let tiles = self.tiles(sources, range: range, calendar: calendar, planMonthlyPrice: planMonthlyPrice)
        let heatmap = self.heatmap(sources, range: range, calendar: calendar)
        let modelShare = self.modelShare(sources, range: range, bucket: bucket, calendar: calendar)
        let projectTrends = self.projectTrends(
            sources,
            range: range,
            identityMode: identityMode,
            calendar: calendar)
        guard !costByModel.isEmpty || tiles != nil || heatmap != nil || modelShare != nil || projectTrends != nil
        else { return nil }

        return DashboardInsightsPayload(
            currencyCode: "USD",
            timeZone: identityMode == .full ? calendar.timeZone.identifier : nil,
            range: DashboardInsightsRangePayload(
                start: self.dayKey(range.lowerBound, calendar: calendar),
                end: self.dayKey(range.upperBound, calendar: calendar),
                days: self.rangeDays),
            bucket: bucket.rawValue,
            costByModel: costByModel.isEmpty ? nil : costByModel,
            tiles: tiles,
            heatmap: heatmap,
            modelShare: modelShare,
            projectTrends: projectTrends)
    }

    // MARK: - Sources

    /// USD scans that cover at least one day, once per provider in payload order.
    static func sources(_ payloads: [CostPayload], calendar: Calendar) -> [Source] {
        var seen = Set<UsageProvider>()
        var sources: [Source] = []
        for payload in payloads {
            guard payload.error == nil,
                  let input = payload.insightSource,
                  input.currencyCode == "USD",
                  let coverage = self.coverage(input, calendar: calendar),
                  seen.insert(input.provider).inserted
            else { continue }
            var days: [DayEntry] = []
            for entry in input.daily {
                guard let day = self.day(entry.date, calendar: calendar), coverage.contains(day) else { continue }
                days.append(DayEntry(day: day, entry: entry))
            }
            sources.append(Source(
                input: input,
                name: ProviderDescriptorRegistry.descriptor(for: input.provider).metadata.displayName,
                coverage: coverage,
                days: days.sorted { $0.day < $1.day }))
        }
        return sources
    }

    /// The days the scan read: its whole history window when coverage is established, only the span it produced
    /// rows for when the scan stopped short, and nothing when coverage is unknown.
    static func coverage(_ input: DashboardCostInsightSource, calendar: Calendar) -> ClosedRange<Date>? {
        let end = calendar.startOfDay(for: input.updatedAt)
        let start = calendar.date(byAdding: .day, value: -(max(1, input.historyDays) - 1), to: end)
            .map { calendar.startOfDay(for: $0) } ?? end
        let scanned = start...end
        if input.historyCoverageIsEstablished {
            return scanned
        }
        guard input.historyScanIsPartial else { return nil }
        let observed = input.daily
            .compactMap { self.day($0.date, calendar: calendar) }
            .filter { scanned.contains($0) }
        guard let first = observed.min(), let last = observed.max() else { return nil }
        return first...last
    }

    static func clip(_ interval: ClosedRange<Date>, to bounds: ClosedRange<Date>) -> ClosedRange<Date>? {
        let start = max(interval.lowerBound, bounds.lowerBound)
        let end = min(interval.upperBound, bounds.upperBound)
        return start <= end ? start...end : nil
    }

    // MARK: - Tiles

    static func tiles(
        _ sources: [Source],
        range: ClosedRange<Date>,
        calendar: Calendar,
        planMonthlyPrice: Double?) -> DashboardInsightTilesPayload?
    {
        let samples = sources.flatMap { self.samples($0, in: range) }
        guard !samples.isEmpty else { return nil }
        let tiles = SpendInsightTiles(
            inputs: SpendInsightInputs(
                period: SpendInsightPeriod(start: range.lowerBound, dayCount: self.rangeDays),
                samples: samples,
                previousSamples: self.previousSamples(sources, range: range, calendar: calendar)),
            calendar: calendar,
            planMonthlyPrice: planMonthlyPrice)
        let topModelShare = tiles.topModelShare.map { share in
            DashboardInsightTilePayload(
                tile: share.tile,
                modelName: share.modelName,
                provider: share.modelID.split(separator: ":", maxSplits: 1).first.map(String.init))
        }
        let payload = DashboardInsightTilesPayload(
            trendBucketCount: tiles.trendBucketCount,
            apiEquivalentCost: tiles.apiEquivalentCost,
            planValue: tiles.planValue.map { DashboardInsightTilePayload(tile: $0) },
            cacheHitRate: tiles.cacheHitRate.map { DashboardInsightTilePayload(tile: $0) },
            costPerMillionTokens: tiles.costPerMillionTokens.map { DashboardInsightTilePayload(tile: $0) },
            topModelShare: topModelShare)
        let hasTile = payload.planValue != nil || payload.cacheHitRate != nil
            || payload.costPerMillionTokens != nil || payload.topModelShare != nil
        return hasTile || payload.apiEquivalentCost != nil ? payload : nil
    }

    /// The equal-length period before the range, offered only when every source covers all of it, so a source
    /// whose history starts inside that period cannot turn the comparison into a floor.
    private static func previousSamples(
        _ sources: [Source],
        range: ClosedRange<Date>,
        calendar: Calendar) -> [SpendInsightSample]?
    {
        guard let start = calendar.date(byAdding: .day, value: -self.rangeDays, to: range.lowerBound),
              let end = calendar.date(byAdding: .day, value: -1, to: range.lowerBound)
        else { return nil }
        let bounds = calendar.startOfDay(for: start)...calendar.startOfDay(for: end)
        let coversPeriod = sources.allSatisfy { source in
            source.coverage.lowerBound <= bounds.lowerBound && source.coverage.upperBound >= bounds.upperBound
        }
        guard coversPeriod else { return nil }
        return sources.flatMap { self.samples($0, in: bounds) }
    }

    static func samples(_ source: Source, in bounds: ClosedRange<Date>) -> [SpendInsightSample] {
        source.entries(in: bounds).map { item -> SpendInsightSample in
            let entry = item.entry
            let cost = self.validCost(entry.costUSD)
            return SpendInsightSample(
                sourceID: source.sourceID,
                day: item.day,
                cost: cost,
                totalTokens: entry.hasOnlyIncompleteRequests ? nil : entry.totalTokens,
                inputTokens: entry.inputTokens,
                cacheReadTokens: entry.cacheReadTokens,
                cacheCreationTokens: entry.cacheCreationTokens,
                outputTokens: entry.outputTokens,
                reasoningTokens: entry.reasoningTokens,
                modelCosts: cost == nil ? [] : self.modelCosts(entry, provider: source.input.provider),
                costCoversTokens: self.costCoversTokens(entry))
        }
    }

    private static func modelCosts(
        _ entry: CostUsageDailyReport.Entry,
        provider: UsageProvider) -> [SpendInsightSample.ModelCost]
    {
        (entry.modelBreakdowns ?? []).compactMap { breakdown -> SpendInsightSample.ModelCost? in
            let name = CostHistoryModelStack.seriesName(breakdown.modelName)
            guard !name.isEmpty, let cost = self.validCost(breakdown.costUSD) else { return nil }
            return SpendInsightSample.ModelCost(id: "\(provider.rawValue):\(name)", name: name, cost: cost)
        }
    }

    /// Unpriced, unmetered or incomplete requests keep their tokens but add no spend, so the day's cost would
    /// understate cost per 1M tokens.
    private static func costCoversTokens(_ entry: CostUsageDailyReport.Entry) -> Bool {
        guard entry.coverageCounts.unpriced == 0,
              entry.coverageCounts.unmetered == 0,
              entry.incompleteRequestCount == 0
        else { return false }
        return !(entry.modelBreakdowns ?? []).contains { breakdown in
            self.validCost(breakdown.costUSD) == nil && (breakdown.totalTokens ?? 0) > 0
        }
    }

    // MARK: - Heatmap

    /// Spend by weekday and hour over the range, from each source's complete hourly buckets.
    static func heatmap(_ sources: [Source], range: ClosedRange<Date>, calendar: Calendar) -> DashboardHeatmapPayload? {
        var samples: [HourOfWeekHeatmapModel.Sample] = []
        for source in sources {
            guard let covered = self.clip(source.coverage, to: range) else { continue }
            for entry in source.input.hourly where covered.contains(calendar.startOfDay(for: entry.hour)) {
                samples.append(HourOfWeekHeatmapModel.Sample(
                    hour: entry.hour,
                    cost: entry.costIsComplete ? entry.costUSD : nil,
                    tokens: entry.tokensAreComplete ? entry.totalTokens : nil))
            }
        }
        let model = HourOfWeekHeatmapModel(samples: samples, calendar: calendar)
        guard model.totalCost > 0, model.totalCost.isFinite else { return nil }
        let makeCell: (HourOfWeekHeatmapModel.Cell) -> DashboardHeatmapCellPayload = { item in
            DashboardHeatmapCellPayload(
                weekday: item.weekday,
                hour: item.hour,
                cost: item.cost,
                share: item.share,
                level: model.level(of: item))
        }
        return DashboardHeatmapPayload(
            weekdays: model.weekdays,
            totalCost: model.totalCost,
            maxCost: model.maxCost,
            weekendShare: model.weekendShare,
            busiest: model.busiestCell.map(makeCell),
            cells: model.cells.filter { $0.cost > 0 }.map(makeCell))
    }

    // MARK: - Helpers

    /// The day, week or month grouping the Usage & Spend window uses for a range of this length.
    static func bucket(for days: ClosedRange<Date>, calendar: Calendar) -> SpendInsightBucket {
        let count = self.dayCount(days, calendar: calendar)
        if count > 180 { return .month }
        if count > 45 { return .week }
        return .day
    }

    static func dayCount(_ days: ClosedRange<Date>, calendar: Calendar) -> Int {
        let first = calendar.startOfDay(for: days.lowerBound)
        let last = calendar.startOfDay(for: days.upperBound)
        return (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
    }

    /// The local day of a `yyyy-MM-dd` key (a longer timestamp keeps its date prefix); `nil` for anything else.
    static func day(_ rawValue: String, calendar: Calendar) -> Date? {
        let key = String(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard key.count == 10,
              parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ part in part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.year == year, components.month == month, components.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func validCost(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
