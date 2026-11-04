import Charts
import CodexBarCore
import SwiftUI

/// Model share over time and project trends for one currency group of the Usage & Spend window.
///
/// Both panels draw series the dashboard model precomputed for the group, and each stays hidden when its
/// range has nothing to show.
struct SpendDashboardInsightsPanels: View {
    let group: SpendDashboardModel.CurrencyGroup
    let hidePersonalInfo: Bool

    var body: some View {
        if let share = self.group.insights.modelShare, share.series.count > 1 {
            SpendModelSharePanel(group: self.group, share: share)
        }
        if let trends = self.group.insights.projectTrends, !trends.trends.isEmpty {
            SpendProjectTrendsPanel(group: self.group, trends: trends, hidePersonalInfo: self.hidePersonalInfo)
        }
    }
}

// MARK: - Model share

private struct SpendModelSharePanel: View {
    let group: SpendDashboardModel.CurrencyGroup
    let share: SpendShareOverTime

    private static let shareTicks = ChartNiceScale.ticks(maximum: 1)

    var body: some View {
        let slots = spendInsightsModelShareSlots(self.share)
        return SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Model share"))
                    .font(.headline)
                Text(self.captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                self.chart(slots: slots)
                MenuBarLayoutChipFlowLayout(spacing: 12) {
                    ForEach(self.share.series) { series in
                        self.legendItem(series, slots: slots)
                    }
                }
            }
        }
    }

    private func chart(slots: [String: ChartPalette.Slot]) -> some View {
        let unit = self.share.bucket.calendarComponent
        let calendar = self.group.calendar
        let domain = spendInsightsDomain(self.group.chartDomain, bucket: self.share.bucket, calendar: calendar)
        return Chart {
            ForEach(self.share.points) { point in
                BarMark(
                    x: .value(L("Day"), point.bucketStart, unit: unit, calendar: calendar),
                    yStart: .value(L("Model share"), point.shareStart),
                    yEnd: .value(L("Model share"), point.shareEnd),
                    width: .ratio(0.8))
                    .foregroundStyle(ChartPalette.color(for: slots[point.seriesID] ?? .other))
                    .accessibilityLabel("\(self.name(point.seriesID)), \(self.dateText(point.bucketStart))")
                    .accessibilityValue(spendInsightsPercentText(point.share))
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: domain, range: .plotDimension(startPadding: 8, endPadding: 8))
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: Self.shareTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let fraction = value.as(Double.self) {
                        Text(spendInsightsPercentText(fraction))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: self.tickStride(domain: domain))) { value in
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(self.axisText(date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
        .frame(height: 180)
        .environment(\.calendar, self.group.calendar)
        .environment(\.timeZone, self.group.timeZone)
        .accessibilityLabel(L("Model share"))
    }

    private func legendItem(_ series: SpendShareOverTime.Series, slots: [String: ChartPalette.Slot]) -> some View {
        let name = self.name(series.id)
        return HStack(spacing: 5) {
            Circle()
                .fill(ChartPalette.color(for: slots[series.id] ?? .other))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
            Text(spendInsightsPercentText(series.share))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize()
        .help(series.isOther ? series.foldedSeriesIDs.map { self.name($0) }.joined(separator: ", ") : name)
        .accessibilityElement(children: .combine)
    }

    private var captionText: String {
        let grouping = switch self.share.bucket {
        case .month: L("Monthly")
        case .week: L("Weekly")
        case .day: L("Daily")
        }
        var parts = [grouping, L("Share of estimated spend")]
        if self.group.modelHistoryCompleteness == .incomplete {
            parts.append(L("Incomplete"))
        }
        return parts.joined(separator: " · ")
    }

    private func name(_ seriesID: String) -> String {
        seriesID == SpendShareOverTime.otherSeriesID
            ? L("Other")
            : self.group.insights.modelNames[seriesID] ?? seriesID
    }

    private func tickStride(domain: ClosedRange<Date>) -> Int {
        let last = max(domain.lowerBound, domain.upperBound.addingTimeInterval(-1))
        let days = Double(SpendDashboardModel.dayCount(in: domain.lowerBound...last, calendar: self.group.calendar))
        return switch self.share.bucket {
        case .month: max(1, Int(ceil(days / 30 / 4)))
        case .week: max(1, Int(ceil(days / 7 / 4)))
        case .day: days > 14 ? 7 : days > 7 ? 3 : 1
        }
    }

    private func axisText(_ date: Date) -> String {
        let format = Date.FormatStyle(
            locale: codexBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone)
        if self.share.bucket == .month {
            return date.formatted(format.year(.twoDigits).month(.abbreviated))
        }
        return date.formatted(format.month().day())
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(
            locale: codexBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone).year().month(.abbreviated).day())
    }
}

// MARK: - Project trends

private struct SpendProjectTrendsPanel: View {
    let group: SpendDashboardModel.CurrencyGroup
    let trends: SpendSeriesTrends
    let hidePersonalInfo: Bool

    var body: some View {
        let rows = spendInsightsProjectTrendRows(
            trends: self.trends.trends,
            identities: self.group.insights.projectIdentities,
            listRows: spendDashboardProjectRows(self.group.projects, isProjectless: false))
        let slots = ChartPalette.slotAssignment(for: self.trends.trends.map { (name: $0.id, total: $0.total) })
        let yUpper = ChartNiceScale.ticks(maximum: self.trends.maximumPointValue).last ?? 1
        let comparisonDays = self.trends.comparisonDayCount
        return SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Project trends"))
                    .font(.headline)
                if comparisonDays > 0 {
                    Text(L("Change compares the last %d days with the %d days before.", comparisonDays, comparisonDays))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(self.trends.trends) { trend in
                        if trend.rank > 1 {
                            Divider()
                        }
                        self.row(
                            trend,
                            ledgerRow: rows[trend.id],
                            allRows: Array(rows.values),
                            color: ChartPalette.color(for: slots[trend.id] ?? .other),
                            yUpper: yUpper)
                    }
                }
            }
        }
    }

    private func row(
        _ trend: SpendSeriesTrends.Trend,
        ledgerRow: SpendDashboardModel.ProjectRow?,
        allRows: [SpendDashboardModel.ProjectRow],
        color: Color,
        yUpper: Double) -> some View
    {
        let identity = ledgerRow?.displayIdentity(hidePersonalInfo: self.hidePersonalInfo)
        let name = identity?.name ?? L("Project %d", trend.rank)
        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                    .help(identity?.path ?? name)
                if let ledgerRow {
                    Text(ledgerRow.providerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let path = identity?.path, ledgerRow?.needsPathDisambiguation(in: allRows) == true {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            Spacer(minLength: 8)
            Chart {
                ForEach(trend.points) { point in
                    LineMark(
                        x: .value(L("Day"), point.bucketStart),
                        y: .value(L("Estimated spend"), point.value))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartYScale(domain: 0...yUpper)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(width: 140, height: 28)
            .accessibilityHidden(true)
            Text(spendDashboardMetricText(cost: trend.total, tokens: nil, currencyCode: self.group.currencyCode))
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)
            Text(spendInsightsChangeText(trend.change))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presentation helpers

/// Palette slots for model share series: kept models by rank, the folded remainder in the neutral Other color.
func spendInsightsModelShareSlots(_ share: SpendShareOverTime) -> [String: ChartPalette.Slot] {
    var slots = ChartPalette.slotAssignment(
        for: share.series.filter { !$0.isOther }.map { (name: $0.id, total: $0.total) })
    slots[SpendShareOverTime.otherSeriesID] = .other
    return slots
}

/// The ledger row behind each project trend, numbered like the Projects list so a redacted label names the same
/// project in both places. A project the list does not show (it follows a selected day) continues the numbering
/// after the list's last rank.
func spendInsightsProjectTrendRows(
    trends: [SpendSeriesTrends.Trend],
    identities: [String: SpendDashboardModel.ProjectRow],
    listRows: [SpendDashboardModel.ProjectRow]) -> [String: SpendDashboardModel.ProjectRow]
{
    let listed = Dictionary(listRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var nextRank = (listRows.map(\.rank).max() ?? 0) + 1
    var rows: [String: SpendDashboardModel.ProjectRow] = [:]
    for trend in trends {
        if let row = listed[trend.id] {
            rows[trend.id] = row
        } else if var row = identities[trend.id] {
            row.rank = nextRank
            nextRank += 1
            rows[trend.id] = row
        }
    }
    return rows
}

/// The chart's x domain: the range widened to whole buckets, like the spend trend chart.
func spendInsightsDomain(
    _ scope: ClosedRange<Date>,
    bucket: SpendInsightBucket,
    calendar: Calendar) -> ClosedRange<Date>
{
    let unit = bucket.calendarComponent
    let start = calendar.dateInterval(of: unit, for: scope.lowerBound)?.start ?? scope.lowerBound
    let last = max(scope.lowerBound, scope.upperBound.addingTimeInterval(-1))
    let end = calendar.dateInterval(of: unit, for: last)?.end ?? scope.upperBound
    return start...max(start, end)
}

func spendInsightsPercentText(_ fraction: Double) -> String {
    fraction.formatted(.percent.precision(.fractionLength(0)).locale(codexBarLocalizedLocale()))
}

/// Signed change between the two halves of the range; "New" when the earlier half had nothing.
func spendInsightsChangeText(_ change: CodexModelsComparison) -> String {
    switch change {
    case .unavailable: "—"
    case .new: L("New")
    case .unchanged: spendInsightsPercentText(0)
    case .ended: "-" + spendInsightsPercentText(1)
    case let .percent(value): (value > 0 ? "+" : "-") + spendInsightsPercentText(abs(value))
    }
}
