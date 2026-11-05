import CodexBarCore
import Foundation

// MARK: - Source

/// The Core cost history behind one provider's dashboard insights.
///
/// `CostPayload` carries it next to its encoded fields but never encodes it, so `codexbar cost` and `/cost` JSON
/// keep their shape while the dashboard snapshot folds the same scan into the Core insight models.
struct DashboardCostInsightSource: Sendable {
    let provider: UsageProvider
    let currencyCode: String
    let historyDays: Int
    let historyCoverageIsEstablished: Bool
    let historyScanIsPartial: Bool
    let updatedAt: Date
    let daily: [CostUsageDailyReport.Entry]
    let hourly: [CostUsageHourlyEntry]
    /// Working-directory projects; empty for providers whose scanner records none.
    let projects: [CostUsageProjectBreakdown]

    init(provider: UsageProvider, snapshot: CostUsageTokenSnapshot) {
        self.provider = provider
        self.currencyCode = snapshot.currencyCode
        self.historyDays = snapshot.historyDays
        self.historyCoverageIsEstablished = snapshot.historyCoverageIsEstablished
        self.historyScanIsPartial = snapshot.historyScanIsPartial
        self.updatedAt = snapshot.updatedAt
        self.daily = snapshot.daily
        self.hourly = snapshot.hourly
        self.projects = provider.supportsLocalProjects ? snapshot.projects : []
    }
}

// MARK: - Payload

/// Additive schema-v1 block with insight charts over local cost history, computed by the same Core models as the
/// Usage & Spend window. Optional members are omitted when they have no data; the block itself is omitted when
/// no USD cost history is available, so snapshots without it keep their previous shape.
struct DashboardInsightsPayload: Encodable {
    let currencyCode: String
    /// Time zone identifier of every day key and of the heatmap's hours; full identity only, since a named
    /// zone hints at where the host is.
    let timeZone: String?
    let range: DashboardInsightsRangePayload
    /// Bucket of the model share chart: `day`, `week` or `month`.
    let bucket: String
    let costByModel: [DashboardCostByModelPayload]?
    let tiles: DashboardInsightTilesPayload?
    let heatmap: DashboardHeatmapPayload?
    let modelShare: DashboardModelSharePayload?
    let projectTrends: DashboardProjectTrendsPayload?
}

struct DashboardInsightsRangePayload: Encodable {
    /// First local day, `yyyy-MM-dd`.
    let start: String
    /// Last local day (the snapshot's generation day), `yyyy-MM-dd`.
    let end: String
    let days: Int
}

// MARK: - Cost by model

/// One provider's daily spend stacked by its top models, with the rest folded into Other.
struct DashboardCostByModelPayload: Encodable {
    let provider: String
    let providerName: String
    /// Model names that get their own series, by rank (0 is the largest).
    let models: [String]
    let hasOther: Bool
    let days: [DashboardCostByModelDayPayload]
}

struct DashboardCostByModelDayPayload: Encodable {
    let date: String
    let total: Double
    /// Bottom-to-top slices; empty when the day reports no model breakdown.
    let segments: [DashboardCostByModelSegmentPayload]
}

struct DashboardCostByModelSegmentPayload: Encodable {
    /// Index into `models`; absent for the Other slice.
    let rank: Int?
    let isOther: Bool
    let value: Double
}

// MARK: - Tiles

struct DashboardInsightTilesPayload: Encodable {
    let trendBucketCount: Int
    let apiEquivalentCost: Double?
    /// Present only when a plan price is configured.
    let planValue: DashboardInsightTilePayload?
    let cacheHitRate: DashboardInsightTilePayload?
    let costPerMillionTokens: DashboardInsightTilePayload?
    let topModelShare: DashboardInsightTilePayload?
}

struct DashboardInsightTilePayload: Encodable {
    let value: Double
    let previousValue: Double?
    let delta: Double?
    /// One value per trend bucket, oldest first; `null` where a bucket has no usable data.
    let trend: [Double?]
    let modelName: String?
    let provider: String?

    init(tile: SpendInsightTiles.Tile, modelName: String? = nil, provider: String? = nil) {
        self.value = tile.value
        self.previousValue = tile.previousValue
        self.delta = tile.delta
        self.trend = tile.trend
        self.modelName = modelName
        self.provider = provider
    }
}

// MARK: - Heatmap

struct DashboardHeatmapPayload: Encodable {
    /// `Calendar` weekday numbers (1 is Sunday) in display order.
    let weekdays: [Int]
    let totalCost: Double
    let maxCost: Double
    let weekendShare: Double?
    let busiest: DashboardHeatmapCellPayload?
    /// Cells with recorded spend only; every other weekday and hour had none.
    let cells: [DashboardHeatmapCellPayload]
}

struct DashboardHeatmapCellPayload: Encodable {
    let weekday: Int
    let hour: Int
    let cost: Double
    let share: Double
    /// Sequential color level from 1 (lightest) to 4 (the busiest quarter).
    let level: Int
}

// MARK: - Model share

struct DashboardModelSharePayload: Encodable {
    let bucket: String
    let total: Double
    let series: [DashboardModelShareSeriesPayload]
    let points: [DashboardModelSharePointPayload]
}

struct DashboardModelShareSeriesPayload: Encodable {
    /// `provider:model`, or `other` for the folded remainder.
    let id: String
    let name: String
    let provider: String?
    let rank: Int
    let total: Double
    let share: Double
    let isOther: Bool
    let foldedCount: Int
}

struct DashboardModelSharePointPayload: Encodable {
    let date: String
    let series: String
    let value: Double
    let share: Double
    let shareStart: Double
    let shareEnd: Double
}

// MARK: - Project trends

struct DashboardProjectTrendsPayload: Encodable {
    let bucket: String
    let start: String
    let end: String
    /// Days in each half of the change comparison.
    let comparisonDays: Int
    let omittedCount: Int
    let maxValue: Double
    let projects: [DashboardProjectTrendPayload]
}

struct DashboardProjectTrendPayload: Encodable {
    let rank: Int
    /// The project name with full identity; otherwise a numbered placeholder.
    let label: String
    /// The working directory with full identity only.
    let path: String?
    let provider: String
    let providerName: String
    let total: Double
    let recentTotal: Double
    let previousTotal: Double
    /// `percent`, `new`, `ended`, `unchanged` or `unavailable`.
    let change: String
    let changeFraction: Double?
    let points: [DashboardTrendPointPayload]
}

struct DashboardTrendPointPayload: Encodable {
    let date: String
    let value: Double
}
