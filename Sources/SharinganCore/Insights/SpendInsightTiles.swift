import Foundation

// MARK: - Inputs

/// One source's usage on one calendar day, reduced to the plain numbers the insight tiles need.
///
/// Token classes mirror `CostUsageDailyReport.Entry`: `nil` means the source did not establish that
/// class, which is never the same as zero. Costs are API-equivalent estimates already converted to
/// the currency the tiles are shown in. Negative or non-finite values are dropped as unknown.
public struct SpendInsightSample: Sendable, Equatable {
    /// Spend attributed to one model on the sample's day.
    public struct ModelCost: Sendable, Equatable {
        /// Provider-qualified key, so equal model names from two providers stay apart.
        public let id: String
        public let name: String
        public let cost: Double

        public init(id: String, name: String, cost: Double) {
            self.id = id
            self.name = name
            self.cost = cost
        }
    }

    public let sourceID: String
    /// Start of the sample's calendar day.
    public let day: Date
    public let cost: Double?
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheCreationTokens: Int?
    public let outputTokens: Int?
    public let reasoningTokens: Int?
    public let modelCosts: [ModelCost]
    /// `false` when some of the day's tokens have no price, so `cost` covers only part of
    /// `totalTokens`. Such days still count as spend but stay out of cost per 1M tokens.
    public let costCoversTokens: Bool

    public init(
        sourceID: String,
        day: Date,
        cost: Double?,
        totalTokens: Int? = nil,
        inputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        modelCosts: [ModelCost] = [],
        costCoversTokens: Bool = true)
    {
        self.sourceID = sourceID
        self.day = day
        self.cost = Self.validCost(cost)
        self.totalTokens = Self.nonnegative(totalTokens)
        self.inputTokens = Self.nonnegative(inputTokens)
        self.cacheReadTokens = Self.nonnegative(cacheReadTokens)
        self.cacheCreationTokens = Self.nonnegative(cacheCreationTokens)
        self.outputTokens = Self.nonnegative(outputTokens)
        self.reasoningTokens = Self.nonnegative(reasoningTokens)
        self.modelCosts = modelCosts.filter { Self.validCost($0.cost) != nil }
        self.costCoversTokens = costCoversTokens
    }

    private static func validCost(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func nonnegative(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

/// The selected range as whole calendar days.
public struct SpendInsightPeriod: Sendable, Equatable {
    /// Start of the range's first day.
    public let start: Date
    /// Number of calendar days in the range, today included.
    public let dayCount: Int

    public init(start: Date, dayCount: Int) {
        self.start = start
        self.dayCount = dayCount
    }
}

/// Everything the insight tiles read, as plain values so the CLI and web dashboard can reuse them.
public struct SpendInsightInputs: Sendable, Equatable {
    public var period: SpendInsightPeriod?
    /// Samples for the selected range. Samples outside it are ignored.
    public var samples: [SpendInsightSample]
    /// Samples for the equal-length period just before the range, or `nil` when history does not
    /// cover that whole period. Samples outside it are ignored.
    public var previousSamples: [SpendInsightSample]?
    /// Days each source's history covers inside the range (start-of-day dates, inclusive). Plan value
    /// spreads a plan's price only over the days its sources cover. Empty when unknown, which counts
    /// every source as covering the whole range.
    public var coverage: [String: ClosedRange<Date>]

    public init(
        period: SpendInsightPeriod? = nil,
        samples: [SpendInsightSample] = [],
        previousSamples: [SpendInsightSample]? = nil,
        coverage: [String: ClosedRange<Date>] = [:])
    {
        self.period = period
        self.samples = samples
        self.previousSamples = previousSamples
        self.coverage = coverage
    }
}

// MARK: - Prompt split

/// A sample's prompt tokens, normalized across provider token conventions.
///
/// Sources disagree on whether `inputTokens` already contains cache reads. Codex and other
/// OpenAI-style sources count cache reads as a subset of input, so their total is
/// `input + output`. Claude, Cursor and Pi report disjoint classes, so their total is
/// `input + cache read + cache write + output`. Reasoning may sit on top of either total. The
/// sample's total decides which convention applies; a sample the total cannot settle is left out
/// rather than guessed.
public struct SpendInsightPromptSplit: Sendable, Equatable {
    /// Every prompt token: uncached input, cache writes and cache reads.
    public let promptTokens: Int
    /// Prompt tokens served from the cache (cache reads).
    public let cachedTokens: Int

    public init(promptTokens: Int, cachedTokens: Int) {
        self.promptTokens = promptTokens
        self.cachedTokens = cachedTokens
    }

    public static func normalized(_ sample: SpendInsightSample) -> SpendInsightPromptSplit? {
        guard let input = sample.inputTokens else { return nil }
        let read = sample.cacheReadTokens ?? 0
        let write = sample.cacheCreationTokens ?? 0
        // Without cache classes both conventions agree: every prompt token is uncached input.
        guard read > 0 || write > 0 else { return SpendInsightPromptSplit(promptTokens: input, cachedTokens: 0) }
        guard let disjointPrompt = CheckedSum.integers([input, read, write]) else { return nil }
        let inclusive = SpendInsightPromptSplit(promptTokens: input, cachedTokens: read)
        let disjoint = SpendInsightPromptSplit(promptTokens: disjointPrompt, cachedTokens: read)
        guard let total = sample.totalTokens else {
            // Without a total, only cache reads larger than all input prove the classes are disjoint.
            return read > input ? disjoint : nil
        }
        let output = sample.outputTokens ?? 0
        let reasoning = sample.reasoningTokens ?? 0
        if read <= input, Self.isTotal(total, sumOf: [input, output], reasoning: reasoning) {
            return inclusive
        }
        if Self.isTotal(total, sumOf: [disjointPrompt, output], reasoning: reasoning) {
            return disjoint
        }
        return nil
    }

    /// Whether `total` equals the parts, with or without reasoning on top.
    private static func isTotal(_ total: Int, sumOf parts: [Int], reasoning: Int) -> Bool {
        guard let sum = CheckedSum.integers(parts) else { return false }
        if total == sum { return true }
        guard reasoning > 0, let withReasoning = CheckedSum.integers([sum, reasoning]) else { return false }
        return total == withReasoning
    }
}

// MARK: - Tiles

/// Insight tiles for the Usage & Spend window, computed over the selected range.
///
/// - Plan value: the API-equivalent spend of sources billed by a priced plan, divided by those plans'
///   prices prorated to the days their sources' history covers, where a plan month counts as
///   `daysPerPlanMonth` days. `nil` without a positive plan price or without spend from a priced source.
/// - Cache hit rate: cache reads divided by all prompt tokens (uncached input, cache writes and cache
///   reads; see `SpendInsightPromptSplit`). Only sources that report cache reads take part.
/// - Cost per 1M tokens: spend divided by all tokens (cache reads included) times one million, over
///   samples that report both spend and tokens and price all of their tokens.
/// - Top model share: the top-spending model's spend divided by all spend on days that report spend,
///   including spend no model claims.
///
/// Each tile carries the same metric for the equal-length period just before the range (when its
/// samples are supplied) and a trend of up to `maximumTrendBucketCount` buckets. Buckets split the
/// range by whole days and differ by at most one day when the range does not divide evenly.
public struct SpendInsightTiles: Sendable, Equatable {
    public static let maximumTrendBucketCount = 12
    /// A 30-day range compares against exactly one month's plan price.
    public static let daysPerPlanMonth = 30.0

    public struct Tile: Sendable, Equatable {
        public let value: Double
        /// The same metric over the previous period; `nil` when that period is not covered by history
        /// or has no data for the metric.
        public let previousValue: Double?
        /// One value per trend bucket, oldest first; `nil` where a bucket has no usable data.
        public let trend: [Double?]

        public init(value: Double, previousValue: Double?, trend: [Double?]) {
            self.value = value
            self.previousValue = previousValue
            self.trend = trend
        }

        /// `value - previousValue`: a fraction for rates and shares, a multiple for plan value.
        public var delta: Double? {
            guard let previousValue else { return nil }
            let delta = self.value - previousValue
            return delta.isFinite ? delta : nil
        }

        /// The change relative to the previous value; `nil` when the previous value is zero.
        public var relativeDelta: Double? {
            guard let previousValue, previousValue > 0, let delta = self.delta else { return nil }
            let relative = delta / previousValue
            return relative.isFinite ? relative : nil
        }
    }

    public struct ModelShare: Sendable, Equatable {
        public let modelID: String
        public let modelName: String
        public let tile: Tile

        public init(modelID: String, modelName: String, tile: Tile) {
            self.modelID = modelID
            self.modelName = modelName
            self.tile = tile
        }
    }

    /// Number of trend buckets: one per day for ranges shorter than `maximumTrendBucketCount`.
    public let trendBucketCount: Int
    /// Known spend over the range; `nil` when no sample reports spend.
    public let apiEquivalentCost: Double?
    public let planValue: Tile?
    public let cacheHitRate: Tile?
    public let costPerMillionTokens: Tile?
    public let topModelShare: ModelShare?

    /// One plan price for every source over the whole range.
    public init(inputs: SpendInsightInputs, calendar: Calendar, planMonthlyPrice: Double?) {
        self.init(
            inputs: inputs,
            calendar: calendar,
            planPricing: planMonthlyPrice.map { SpendInsightPlanPricing.unscoped(monthlyPrice: $0) })
    }

    public init(inputs: SpendInsightInputs, calendar: Calendar, planPricing: SpendInsightPlanPricing?) {
        guard let period = inputs.period, period.dayCount > 0 else {
            self.trendBucketCount = 0
            self.apiEquivalentCost = nil
            self.planValue = nil
            self.cacheHitRate = nil
            self.costPerMillionTokens = nil
            self.topModelShare = nil
            return
        }
        let window = Window(period: period, calendar: calendar)
        let cacheSources = Self.cacheReportingSources(inputs.samples + (inputs.previousSamples ?? []))
        var current = Totals()
        var buckets = Array(repeating: Totals(), count: window.bucketCount)
        for sample in inputs.samples {
            guard let bucket = window.bucket(of: sample.day) else { continue }
            current.add(sample, cacheSources: cacheSources)
            buckets[bucket].add(sample, cacheSources: cacheSources)
        }
        let previous: Totals? = inputs.previousSamples.map { samples -> Totals in
            var totals = Totals()
            for sample in samples where window.isInPreviousPeriod(sample.day) {
                totals.add(sample, cacheSources: cacheSources)
            }
            return totals
        }

        self.trendBucketCount = window.bucketCount
        self.apiEquivalentCost = current.apiEquivalentCost
        self.planValue = planPricing.flatMap { pricing in
            Self.planValueTile(inputs: inputs, period: period, calendar: calendar, pricing: pricing)
        }
        self.cacheHitRate = Self.tile(
            current.cacheHitRate,
            previous: previous?.cacheHitRate,
            trend: buckets.map(\.cacheHitRate))
        self.costPerMillionTokens = Self.tile(
            current.costPerMillionTokens,
            previous: previous?.costPerMillionTokens,
            trend: buckets.map(\.costPerMillionTokens))
        if let model = current.topModel,
           let tile = Self.tile(
               current.share(of: model.id),
               previous: previous?.share(of: model.id),
               trend: buckets.map { $0.share(of: model.id) })
        {
            self.topModelShare = ModelShare(modelID: model.id, modelName: model.name, tile: tile)
        } else {
            self.topModelShare = nil
        }
    }

    private static func tile(_ value: Double?, previous: Double?, trend: [Double?]) -> Tile? {
        guard let value, value.isFinite else { return nil }
        return Tile(value: value, previousValue: previous, trend: trend)
    }

    /// Sources that report cache reads anywhere. Their missing cache reads count as zero, since
    /// some scanners omit a zero class; sources that never report one stay out of the hit rate.
    private static func cacheReportingSources(_ samples: [SpendInsightSample]) -> Set<String> {
        Set(samples.filter { $0.cacheReadTokens != nil }.map(\.sourceID))
    }
}

// MARK: - Bucketing

extension SpendInsightTiles {
    private struct Window {
        let start: Date
        let dayCount: Int
        let bucketCount: Int
        let calendar: Calendar

        init(period: SpendInsightPeriod, calendar: Calendar) {
            self.start = calendar.startOfDay(for: period.start)
            self.dayCount = period.dayCount
            self.bucketCount = min(SpendInsightTiles.maximumTrendBucketCount, period.dayCount)
            self.calendar = calendar
        }

        /// The trend bucket holding `day`, or `nil` outside the selected range.
        func bucket(of day: Date) -> Int? {
            guard let index = self.dayIndex(of: day), index >= 0, index < self.dayCount else { return nil }
            return index * self.bucketCount / self.dayCount
        }

        func isInPreviousPeriod(_ day: Date) -> Bool {
            guard let index = self.dayIndex(of: day) else { return false }
            return index >= -self.dayCount && index < 0
        }

        /// Days in `bucket`; buckets differ by at most one day when the range does not divide evenly.
        func dayCount(ofBucket bucket: Int) -> Int {
            Self.ceilingDivide((bucket + 1) * self.dayCount, by: self.bucketCount)
                - Self.ceilingDivide(bucket * self.dayCount, by: self.bucketCount)
        }

        /// Day indices of the range that a plan's sources cover: the span from the earliest covered
        /// day to the latest. Without coverage data every day counts.
        func coveredDays(of plan: SpendInsightPlanPricing.Plan, coverage: [String: ClosedRange<Date>]) -> [Int] {
            guard !coverage.isEmpty else { return Array(0..<self.dayCount) }
            let intervals = coverage.filter { plan.covers($0.key) }.map(\.value)
            guard let first = intervals.map(\.lowerBound).min(),
                  let last = intervals.map(\.upperBound).max(),
                  let start = self.dayIndex(of: first),
                  let end = self.dayIndex(of: last)
            else { return [] }
            let lower = max(0, start)
            let upper = min(self.dayCount - 1, end)
            return lower <= upper ? Array(lower...upper) : []
        }

        private func dayIndex(of day: Date) -> Int? {
            self.calendar.dateComponents([.day], from: self.start, to: self.calendar.startOfDay(for: day)).day
        }

        private static func ceilingDivide(_ value: Int, by divisor: Int) -> Int {
            (value + divisor - 1) / divisor
        }
    }
}

// MARK: - Totals

extension SpendInsightTiles {
    private struct TopModel {
        let id: String
        let name: String
    }

    private struct Totals {
        private var knownCost = 0.0
        private var sawCost = false
        private var pairedCost = 0.0
        private var pairedTokens = 0
        private var pairedTokensOverflowed = false
        private var promptTokens = 0
        private var cachedTokens = 0
        private var promptTokensOverflowed = false
        private var shareSpend = 0.0
        private var modelCosts: [String: Double] = [:]
        private var modelNames: [String: String] = [:]

        mutating func add(_ sample: SpendInsightSample, cacheSources: Set<String>) {
            if let cost = sample.cost {
                self.sawCost = true
                self.knownCost += cost
                var attributed = 0.0
                for model in sample.modelCosts {
                    self.modelCosts[model.id, default: 0] += model.cost
                    if self.modelNames[model.id] == nil {
                        self.modelNames[model.id] = model.name
                    }
                    attributed += model.cost
                }
                // Model rows can only claim spend the day reports; never let them exceed it.
                self.shareSpend += max(cost, attributed)
                if let tokens = sample.totalTokens, sample.costCoversTokens {
                    self.pairedCost += cost
                    let addition = self.pairedTokens.addingReportingOverflow(tokens)
                    self.pairedTokensOverflowed = self.pairedTokensOverflowed || addition.overflow
                    self.pairedTokens = addition.partialValue
                }
            }
            if cacheSources.contains(sample.sourceID), let split = SpendInsightPromptSplit.normalized(sample) {
                let prompt = self.promptTokens.addingReportingOverflow(split.promptTokens)
                let cached = self.cachedTokens.addingReportingOverflow(split.cachedTokens)
                self.promptTokensOverflowed = self.promptTokensOverflowed || prompt.overflow || cached.overflow
                self.promptTokens = prompt.partialValue
                self.cachedTokens = cached.partialValue
            }
        }

        var apiEquivalentCost: Double? {
            self.sawCost && self.knownCost.isFinite ? self.knownCost : nil
        }

        var costPerMillionTokens: Double? {
            guard !self.pairedTokensOverflowed, self.pairedTokens > 0 else { return nil }
            let value = self.pairedCost * 1_000_000 / Double(self.pairedTokens)
            return value.isFinite ? value : nil
        }

        var cacheHitRate: Double? {
            guard !self.promptTokensOverflowed, self.promptTokens > 0 else { return nil }
            return Double(self.cachedTokens) / Double(self.promptTokens)
        }

        /// The model with the most spend; ties go to the name, then the key, in ascending order.
        var topModel: TopModel? {
            self.modelCosts
                .filter { $0.value > 0 && $0.value.isFinite }
                .min { lhs, rhs in self.ranksAhead(lhs, rhs) }
                .map { TopModel(id: $0.key, name: self.modelNames[$0.key] ?? $0.key) }
        }

        func share(of modelID: String) -> Double? {
            guard self.shareSpend > 0, self.shareSpend.isFinite else { return nil }
            let value = (self.modelCosts[modelID] ?? 0) / self.shareSpend
            return value.isFinite ? min(1, value) : nil
        }

        private func ranksAhead(_ lhs: (key: String, value: Double), _ rhs: (key: String, value: Double)) -> Bool {
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            let lhsName = self.modelNames[lhs.key] ?? lhs.key
            let rhsName = self.modelNames[rhs.key] ?? rhs.key
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.key < rhs.key
        }
    }
}

// MARK: - Plan value

extension SpendInsightTiles {
    /// Spend from priced sources and the prices spread over their covered days, for one span of days.
    private struct PlanTotals {
        private var cost = 0.0
        private var sawCost = false
        /// Sum over plans of the monthly price times the days its sources cover.
        var priceDays = 0.0

        mutating func add(cost: Double) {
            self.cost += cost
            self.sawCost = true
        }

        var value: Double? {
            guard self.sawCost, self.priceDays > 0, self.cost.isFinite else { return nil }
            let value = self.cost / (self.priceDays / SpendInsightTiles.daysPerPlanMonth)
            return value.isFinite ? value : nil
        }
    }

    /// Plan value compares each priced plan's own sources with that plan's price, so spend from sources
    /// without a price stays out, and a price counts only for the days its sources' history covers.
    private static func planValueTile(
        inputs: SpendInsightInputs,
        period: SpendInsightPeriod,
        calendar: Calendar,
        pricing: SpendInsightPlanPricing) -> Tile?
    {
        let window = Window(period: period, calendar: calendar)
        guard !pricing.isEmpty, window.dayCount > 0, window.bucketCount > 0 else { return nil }
        var current = PlanTotals()
        var buckets = Array(repeating: PlanTotals(), count: window.bucketCount)
        for plan in pricing.plans {
            for day in window.coveredDays(of: plan, coverage: inputs.coverage) {
                current.priceDays += plan.monthlyPrice
                buckets[day * window.bucketCount / window.dayCount].priceDays += plan.monthlyPrice
            }
        }
        for sample in inputs.samples where pricing.covers(sample.sourceID) {
            guard let cost = sample.cost, let bucket = window.bucket(of: sample.day) else { continue }
            current.add(cost: cost)
            buckets[bucket].add(cost: cost)
        }
        // Previous samples exist only when every source covers that whole period.
        let previous: PlanTotals? = inputs.previousSamples.map { samples -> PlanTotals in
            var totals = PlanTotals()
            totals.priceDays = pricing.monthlyPrice * Double(window.dayCount)
            for sample in samples where pricing.covers(sample.sourceID) && window.isInPreviousPeriod(sample.day) {
                if let cost = sample.cost {
                    totals.add(cost: cost)
                }
            }
            return totals
        }
        return Self.tile(current.value, previous: previous?.value, trend: buckets.map(\.value))
    }
}
