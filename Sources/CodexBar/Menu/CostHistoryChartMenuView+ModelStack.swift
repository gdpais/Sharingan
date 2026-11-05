import AppKit
import Charts
import CodexBarCore
import SwiftUI

/// Colors and labels for a cost history chart stacked by model (`CostHistoryModelStack`): the
/// stacked models take the first `ChartPalette` slots by rank and the folded rest takes the
/// neutral "Other" gray. Models are ranked once for every metric, so switching between cost and
/// tokens never swaps their colors.
struct CostHistoryStackPresentation {
    struct BarSegment: Identifiable {
        let id: String
        let date: Date
        let start: Double
        let end: Double
        let title: String
        let color: Color
        let series: CostHistoryModelStack.Series
    }

    struct LegendItem: Identifiable {
        let id: String
        let title: String
        let color: Color
        let isOther: Bool
    }

    /// Trimmed model names with their own series, by rank.
    let models: [String]
    let segments: [BarSegment]
    let legendItems: [LegendItem]
    /// Plotted dates whose bar is drawn as segments instead of a single bar.
    let stackedDates: Set<Date>
    let stackedDayKeys: Set<String>
    let paletteMode: ChartPaletteMode

    /// Nil when nothing stacks, so the chart keeps its single-color bars. `rankedModels` (see
    /// `CostHistoryModelStack.stableTopModels`) keeps one ranking across metrics; without it the
    /// models rank by `metric`.
    init?(
        bars: [(entry: CostUsageDailyReport.Entry, total: Double, date: Date)],
        metric: CostHistoryModelStack.Metric,
        rankedModels: [String]? = nil,
        paletteMode: ChartPaletteMode = .accents)
    {
        let stackInput = bars.map { (entry: $0.entry, total: $0.total) }
        let stack: CostHistoryModelStack.Stack? = if let rankedModels {
            CostHistoryModelStack.stack(stackInput, metric: metric, models: rankedModels)
        } else {
            CostHistoryModelStack.stack(stackInput, metric: metric)
        }
        guard let stack else { return nil }
        let titles = stack.models.map(UsageFormatter.modelDisplayName)

        var segments: [BarSegment] = []
        var stackedDates = Set<Date>()
        var stackedDayKeys = Set<String>()
        var seriesInUse = Set<CostHistoryModelStack.Series>()
        for (barIndex, bar) in bars.enumerated() {
            guard let daySegments = stack.segmentsByDayKey[bar.entry.date] else { continue }
            stackedDates.insert(bar.date)
            stackedDayKeys.insert(bar.entry.date)
            for (segmentIndex, segment) in daySegments.enumerated() {
                seriesInUse.insert(segment.series)
                segments.append(BarSegment(
                    id: "\(barIndex)-\(segmentIndex)",
                    date: bar.date,
                    start: segment.start,
                    end: segment.end,
                    title: Self.title(for: segment.series, titles: titles),
                    color: Self.color(for: segment.series, mode: paletteMode),
                    series: segment.series))
            }
        }

        var legendItems: [LegendItem] = []
        for (rank, title) in titles.enumerated() where seriesInUse.contains(.model(rank)) {
            legendItems.append(LegendItem(
                id: "model-\(rank)",
                title: title,
                color: Self.color(for: .model(rank), mode: paletteMode),
                isOther: false))
        }
        if seriesInUse.contains(.other) {
            legendItems.append(LegendItem(
                id: "other",
                title: Self.title(for: .other, titles: titles),
                color: Self.color(for: .other, mode: paletteMode),
                isOther: true))
        }

        self.models = stack.models
        self.segments = segments
        self.legendItems = legendItems
        self.stackedDates = stackedDates
        self.stackedDayKeys = stackedDayKeys
        self.paletteMode = paletteMode
    }

    /// The legend color for a model row: its stacked series, or "Other" when it folds.
    func accentColor(forModel name: String) -> Color {
        guard let rank = self.models.firstIndex(of: CostHistoryModelStack.seriesName(name)) else {
            return Self.color(for: .other, mode: self.paletteMode)
        }
        return Self.color(for: .model(rank), mode: self.paletteMode)
    }

    /// Series colors in the provider-accent palette (today's colors).
    static func color(for series: CostHistoryModelStack.Series) -> Color {
        self.color(for: series, mode: .accents)
    }

    static func color(for series: CostHistoryModelStack.Series, mode: ChartPaletteMode) -> Color {
        switch series {
        case let .model(rank): ChartPalette.color(for: .index(rank), mode: mode)
        case .other: ChartPalette.otherColor(mode: mode)
        }
    }

    /// Series in bottom-to-top stacking order: the ranked models, then "Other".
    var seriesOrder: [CostHistoryModelStack.Series] {
        self.models.indices.map { CostHistoryModelStack.Series.model($0) } + [.other]
    }

    func title(for series: CostHistoryModelStack.Series) -> String {
        Self.title(for: series, titles: self.models.map(UsageFormatter.modelDisplayName))
    }

    private static func title(for series: CostHistoryModelStack.Series, titles: [String]) -> String {
        switch series {
        case let .model(rank):
            titles.indices.contains(rank) ? titles[rank] : L("Other")
        case .other:
            L("Other")
        }
    }
}

/// One-line legend under the stacked cost chart: swatches in series colors, names in label colors.
struct CostHistoryStackLegend: View {
    static let height: CGFloat = 14

    let items: [CostHistoryStackPresentation.LegendItem]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(self.items) { item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 7, height: 7)
                    Text(item.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // Long model names truncate before the short "Other" label does.
                .layoutPriority(item.isOther ? 1 : 0)
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.height, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension CostHistoryChartMenuView {
    /// Faint enough to sit behind bars without reading as data.
    static let weekendShadeColor = Color(nsColor: .labelColor).opacity(0.05)

    static func stackMetric(_ metric: ChartMetric) -> CostHistoryModelStack.Metric {
        switch metric {
        case .tokens: .tokens
        case .cost: .cost
        }
    }

    /// Model stack for one metric over the plotted days; nil when nothing stacks. Models rank once
    /// over all plotted days (`stableTopModels`), so both metrics give a model the same color.
    static func stackPresentation(
        provider: UsageProvider,
        sortedDaily: [DailyEntry],
        metric: ChartMetric,
        paletteMode: ChartPaletteMode = .accents) -> CostHistoryStackPresentation?
    {
        let bars = sortedDaily.compactMap { entry -> (entry: DailyEntry, total: Double, date: Date)? in
            guard let input = self.chartPointInput(for: entry, provider: provider, metric: metric) else { return nil }
            return (entry: entry, total: input.value, date: input.date)
        }
        return CostHistoryStackPresentation(
            bars: bars,
            metric: self.stackMetric(metric),
            rankedModels: CostHistoryModelStack.stableTopModels(sortedDaily),
            paletteMode: paletteMode)
    }

    /// The legend row is reserved when any metric stacks, so switching metrics never changes the
    /// menu's measured height.
    static func reservesStackLegendRow(
        provider: UsageProvider,
        sortedDaily: [DailyEntry],
        activeStack: CostHistoryStackPresentation?,
        activeMetric: ChartMetric) -> Bool
    {
        if activeStack != nil { return true }
        return ChartMetric.allCases.contains { metric in
            metric != activeMetric
                && self.stackPresentation(provider: provider, sortedDaily: sortedDaily, metric: metric) != nil
        }
    }

    /// "+12% vs previous 30 days" for the cost summary; nil when there is nothing honest to compare.
    /// A subtotal with incomplete requests is a lower bound, so it never gets a delta.
    static func previousPeriodDeltaText(
        currentCostUSD: Double?,
        previousPeriodCostUSD: Double?,
        historyDays: Int,
        incompleteCount: Int) -> String?
    {
        guard incompleteCount == 0,
              let delta = CostHistoryModelStack.periodDelta(
                  currentTotal: currentCostUSD,
                  previousPeriodTotal: previousPeriodCostUSD,
                  days: historyDays)
        else { return nil }
        let percent = delta.formatted(.percent
            .precision(.fractionLength(0))
            .sign(strategy: .always(includingZero: false))
            .locale(codexBarLocalizedLocale()))
        return L("%@ vs previous %d days", percent, historyDays)
    }

    @ChartContentBuilder
    static func weekendShading(_ intervals: [DateInterval]) -> some ChartContent {
        ForEach(intervals, id: \.self) { interval in
            RectangleMark(
                xStart: .value(L("Day"), interval.start),
                xEnd: .value(L("Day"), interval.end))
                .foregroundStyle(Self.weekendShadeColor)
                .accessibilityHidden(true)
        }
    }

    @ChartContentBuilder
    static func stackedBars(
        _ segments: [CostHistoryStackPresentation.BarSegment],
        metricTitle: String) -> some ChartContent
    {
        ForEach(segments) { segment in
            BarMark(
                x: .value(L("Day"), segment.date, unit: .day),
                yStart: .value(metricTitle, segment.start),
                yEnd: .value(metricTitle, segment.end),
                width: .ratio(ChartBarHoverSelection.barWidthRatio))
                .foregroundStyle(segment.color)
                .accessibilityLabel(segment.title)
        }
    }

    static func _stackForTesting(
        provider: UsageProvider,
        daily: [DailyEntry],
        metric: ChartMetric) -> CostHistoryStackPresentation?
    {
        self.stackPresentation(
            provider: provider,
            sortedDaily: daily.sorted { $0.date < $1.date },
            metric: metric)
    }

    static func _reservesStackLegendRowForTesting(
        provider: UsageProvider,
        daily: [DailyEntry],
        metric: ChartMetric) -> Bool
    {
        let sorted = daily.sorted { $0.date < $1.date }
        return self.reservesStackLegendRow(
            provider: provider,
            sortedDaily: sorted,
            activeStack: self.stackPresentation(provider: provider, sortedDaily: sorted, metric: metric),
            activeMetric: metric)
    }
}
