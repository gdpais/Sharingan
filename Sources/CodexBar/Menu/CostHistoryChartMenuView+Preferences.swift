import Charts
import CodexBarCore
import SwiftUI

/// One plotted day with a value for the active metric.
struct CostHistoryPlotPoint: Identifiable, Equatable {
    let date: Date
    let value: Double

    var id: Date {
        self.date
    }
}

/// One series' band on one day of the stacked area (line style with stacking on).
struct CostHistoryAreaBand: Identifiable {
    let id: String
    let seriesID: String
    let title: String
    let date: Date
    let start: Double
    let end: Double
    let color: Color
}

extension CostHistoryChartMenuView {
    /// Opacity of stacked areas, so the hairline gridlines stay visible through them.
    static let areaOpacity = 0.85

    // MARK: - Marks

    /// The day series in the chosen style. Bars: stacked segments on days with a model breakdown and one
    /// bar elsewhere (today's chart). Line: stacked areas per series when stacking is on, otherwise one line.
    @ChartContentBuilder
    static func seriesMarks(
        _ points: [CostHistoryPlotPoint],
        stack: CostHistoryStackPresentation?,
        style: ChartPreferences.Style,
        color: Color,
        metricTitle: String) -> some ChartContent
    {
        if style == .line, let stack {
            self.stackedAreas(self.areaBands(points: points, stack: stack), metricTitle: metricTitle)
        } else if style == .line {
            self.totalLine(points, color: color, metricTitle: metricTitle)
        } else if let stack {
            self.stackedBars(stack.segments, metricTitle: metricTitle)
            self.singleBars(
                points.filter { !stack.stackedDates.contains($0.date) },
                color: color,
                metricTitle: metricTitle)
        } else {
            self.singleBars(points, color: color, metricTitle: metricTitle)
        }
    }

    @ChartContentBuilder
    static func singleBars(_ points: [CostHistoryPlotPoint], color: Color, metricTitle: String) -> some ChartContent {
        ForEach(points) { point in
            BarMark(
                x: .value(L("Day"), point.date, unit: .day),
                y: .value(metricTitle, point.value),
                width: .ratio(ChartBarHoverSelection.barWidthRatio))
                .foregroundStyle(color)
        }
    }

    @ChartContentBuilder
    static func totalLine(_ points: [CostHistoryPlotPoint], color: Color, metricTitle: String) -> some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value(L("Day"), point.date, unit: .day),
                y: .value(metricTitle, point.value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                // Dots keep a single plotted day visible, as in the plugin line charts.
                .symbol(.circle)
                .symbolSize(9)
        }
    }

    @ChartContentBuilder
    static func stackedAreas(_ bands: [CostHistoryAreaBand], metricTitle: String) -> some ChartContent {
        ForEach(bands) { band in
            AreaMark(
                x: .value(L("Day"), band.date, unit: .day),
                yStart: .value(metricTitle, band.start),
                yEnd: .value(metricTitle, band.end),
                series: .value("Series", band.seriesID))
                .foregroundStyle(band.color.opacity(Self.areaOpacity))
                .accessibilityLabel(band.title)
        }
    }

    // MARK: - Stacked areas

    /// Bands for every series in use on every plotted day, so each area runs the whole range. A day with a
    /// model breakdown stacks its segments; a day without one has no attributable models, so its whole
    /// value is "Other". Each day's top band ends at the day's total, as its bar would.
    static func areaBands(
        points: [CostHistoryPlotPoint],
        stack: CostHistoryStackPresentation) -> [CostHistoryAreaBand]
    {
        var segmentsByDate: [Date: [CostHistoryStackPresentation.BarSegment]] = [:]
        for segment in stack.segments {
            segmentsByDate[segment.date, default: []].append(segment)
        }
        let unstackedDayHasValue = points.contains { segmentsByDate[$0.date] == nil && $0.value > 0 }
        let seriesInUse = Set(stack.segments.map(\.series))
        let order = stack.seriesOrder.filter { seriesInUse.contains($0) || ($0 == .other && unstackedDayHasValue) }

        var bands: [CostHistoryAreaBand] = []
        for point in points {
            let daySegments = segmentsByDate[point.date]
            var cursor = 0.0
            for series in order {
                let height: Double = if let daySegments {
                    daySegments.first { $0.series == series }.map { $0.end - $0.start } ?? 0
                } else {
                    series == .other ? point.value : 0
                }
                let seriesID = Self.seriesID(series)
                bands.append(CostHistoryAreaBand(
                    id: "\(seriesID)-\(Int(point.date.timeIntervalSince1970))",
                    seriesID: seriesID,
                    title: stack.title(for: series),
                    date: point.date,
                    start: cursor,
                    end: cursor + max(0, height),
                    color: CostHistoryStackPresentation.color(for: series, mode: stack.paletteMode)))
                cursor += max(0, height)
            }
        }
        return bands
    }

    private static func seriesID(_ series: CostHistoryModelStack.Series) -> String {
        switch series {
        case let .model(rank): "model-\(rank)"
        case .other: "other"
        }
    }

    // MARK: - Range

    /// The entries the cost history chart plots for `preferences`: the snapshot's days, narrowed to the
    /// chosen range when it is shorter than the History window. Nil keeps the chart on all of them.
    static func plottedDaily(
        _ snapshot: CostUsageTokenSnapshot,
        preferences: ChartPreferences,
        historyDays: Int,
        calendar: Calendar) -> [DailyEntry]?
    {
        guard preferences.plottedDays(historyDays: historyDays) < max(1, historyDays) else { return nil }
        return preferences.plottedEntries(
            snapshot.daily,
            historyDays: historyDays,
            now: snapshot.updatedAt,
            calendar: calendar)
    }

    // MARK: - Previous period

    /// Source-currency cost of the window before the History window, for "+12% vs previous 30 days".
    /// Nil unless the window is rolling, both windows were fully read, and the token refresh read the
    /// previous one (`CostUsageTokenSnapshot.previousPeriodDaily`).
    static func previousPeriodCostUSD(
        _ snapshot: CostUsageTokenSnapshot,
        historyDays: Int,
        calendar: Calendar) -> Double?
    {
        guard snapshot.reportingPeriod == nil,
              snapshot.historyIsFullyScanned,
              let previous = snapshot.previousPeriodDaily
        else { return nil }
        return CostHistoryModelStack.previousPeriodTotal(
            previous,
            days: historyDays,
            now: snapshot.updatedAt,
            metric: .cost,
            calendar: calendar)
    }
}
