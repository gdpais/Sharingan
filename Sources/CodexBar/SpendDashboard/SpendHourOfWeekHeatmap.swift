import CodexBarCore
import Foundation
import SwiftUI

// MARK: - Hour-of-week inputs

extension SpendTrendChartModel {
    /// Folds the same recorded points the hourly drill-down draws. They cover the whole reporting
    /// range unless a day is selected, in which case the dashboard model keeps only that day's hours.
    static func hourOfWeekSamples(
        group: SpendDashboardModel.CurrencyGroup,
        sourceID: String? = nil) -> [HourOfWeekHeatmapModel.Sample]
    {
        let domain = group.chartDomain
        return group.hourlyPoints.filter { point in
            point.hour >= domain.lowerBound && point.hour < domain.upperBound
                && (sourceID == nil || point.sourceID == sourceID)
        }.map { HourOfWeekHeatmapModel.Sample(hour: $0.hour, cost: $0.cost) }
    }

    static func hourOfWeekLegendProviders(
        in group: SpendDashboardModel.CurrencyGroup) -> [SpendDashboardModel.ProviderRow]
    {
        let domain = group.chartDomain
        let sourceIDs = Set(group.hourlyPoints.filter {
            $0.hour >= domain.lowerBound && $0.hour < domain.upperBound
        }.map(\.sourceID))
        return group.providers.filter { sourceIDs.contains($0.id) }
    }

    /// The statistics time zone with the viewer's first weekday and the app language's day names.
    static func hourOfWeekCalendar(
        group: SpendDashboardModel.CurrencyGroup,
        firstWeekday: Int,
        locale: Locale) -> Calendar
    {
        var calendar = group.calendar
        calendar.locale = locale
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func hourOfWeekWeekdayText(_ weekday: Int, calendar: Calendar) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
    }

    /// Clock notation is language independent, like the hourly drill-down's axis.
    static func hourOfWeekClockText(_ hour: Int) -> String {
        String(format: "%02d:00", locale: Locale(identifier: "en_US_POSIX"), hour)
    }
}

// MARK: - View

/// Spend by weekday and hour over the selected range, so heavy work can be lined up with resets.
struct SpendHourOfWeekHeatmap: View {
    let group: SpendDashboardModel.CurrencyGroup
    var sourceID: String?
    var firstWeekday = Calendar.autoupdatingCurrent.firstWeekday

    var body: some View {
        let calendar = SpendTrendChartModel.hourOfWeekCalendar(
            group: self.group,
            firstWeekday: self.firstWeekday,
            locale: codexBarLocalizedLocale())
        let model = HourOfWeekHeatmapModel(
            samples: SpendTrendChartModel.hourOfWeekSamples(group: self.group, sourceID: self.sourceID),
            calendar: calendar)
        // Hover state lives in the grid so pointer moves do not refold the range.
        SpendHourOfWeekGrid(group: self.group, sourceID: self.sourceID, model: model, calendar: calendar)
    }
}

private struct SpendHourOfWeekGrid: View {
    let group: SpendDashboardModel.CurrencyGroup
    let sourceID: String?
    let model: HourOfWeekHeatmapModel
    let calendar: Calendar

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hoveredCellID: Int?

    private static let cellHeight: CGFloat = 18
    private static let cellSpacing: CGFloat = 2
    private static let labeledHours = [0, 6, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(self.scopeText)
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .help(self.group.timeZone.identifier)
                .accessibilityIdentifier("spend-hour-of-week-scope")
            if self.model.isEmpty {
                ContentUnavailableView(L("Spend unavailable"), systemImage: "calendar")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                self.summary
                self.grid
                self.footer
            }
        }
    }

    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                self.totalSummary
                Spacer()
                self.peakSummary
            }
            VStack(alignment: .leading, spacing: 5) {
                self.totalSummary
                self.peakSummary
            }
        }
        .font(.caption)
    }

    private var totalSummary: some View {
        HStack(spacing: 8) {
            Text(L("Recorded spend")).foregroundStyle(.secondary)
            Text(self.costText(self.model.totalCost)).font(.headline).monospacedDigit()
        }
    }

    @ViewBuilder
    private var peakSummary: some View {
        if let busiest = self.model.busiestCell {
            HStack(spacing: 8) {
                Text(L("Peak hour")).foregroundStyle(.secondary)
                Text(self.cellText(busiest)).monospacedDigit()
            }
        }
    }

    private var grid: some View {
        let palette = SpendActivityPalette(colorScheme: self.colorScheme, contrast: self.contrast)
        return HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: Self.cellSpacing) {
                ForEach(0..<HourOfWeekHeatmapModel.daysPerWeek, id: \.self) { row in
                    Text(self.weekdayText(row: row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: Self.cellHeight)
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Self.cellSpacing) {
                ForEach(0..<HourOfWeekHeatmapModel.daysPerWeek, id: \.self) { row in
                    HStack(spacing: Self.cellSpacing) {
                        ForEach(0..<HourOfWeekHeatmapModel.hoursPerDay, id: \.self) { hour in
                            if let cell = self.model.cell(row: row, hour: hour) {
                                self.cellView(cell, palette: palette)
                            }
                        }
                    }
                }
                self.hourAxis.padding(.top, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SpendDashboardTrendSection.hourOfWeek.title)
        .accessibilityIdentifier("spend-hour-of-week-heatmap")
    }

    private func cellView(_ cell: HourOfWeekHeatmapModel.Cell, palette: SpendActivityPalette) -> some View {
        let text = self.cellText(cell)
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        return shape
            .fill(palette.color(forLevel: self.model.level(of: cell)))
            .frame(maxWidth: .infinity)
            .frame(height: Self.cellHeight)
            .overlay {
                if self.hoveredCellID == cell.id {
                    shape.stroke(Color.primary.opacity(0.7), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    self.hoveredCellID = cell.id
                } else if self.hoveredCellID == cell.id {
                    self.hoveredCellID = nil
                }
            }
            .help(text)
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    /// Equal-width segments of six columns line up with the cells because both rows share spacing.
    private var hourAxis: some View {
        HStack(spacing: Self.cellSpacing) {
            ForEach(Self.labeledHours, id: \.self) { hour in
                Text(SpendTrendChartModel.hourOfWeekClockText(hour))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private var footer: some View {
        let palette = SpendActivityPalette(colorScheme: self.colorScheme, contrast: self.contrast)
        return HStack(spacing: 4) {
            if let cell = self.hoveredCell {
                Text(self.cellText(cell)).monospacedDigit()
            } else if let share = self.model.weekendShare {
                Text(L("%@ of spend on weekends", UsageFormatter.percentString(share * 100)))
            }
            Spacer()
            Text(L("Less"))
            ForEach(0...4, id: \.self) { level in
                SpendActivitySwatch(palette: palette, level: level)
            }
            Text(L("More"))
        }
        .font(.callout)
        .foregroundStyle(.primary.opacity(0.75))
    }

    private var hoveredCell: HourOfWeekHeatmapModel.Cell? {
        guard let id = self.hoveredCellID else { return nil }
        return self.model.cells.first { $0.id == id }
    }

    private var scopeText: String {
        let domain = self.group.chartDomain
        let last = max(domain.lowerBound, domain.upperBound.addingTimeInterval(-1))
        let start = SpendTrendChartModel.utcOffsetText(domain.lowerBound, timeZone: self.group.timeZone)
        let end = SpendTrendChartModel.utcOffsetText(last, timeZone: self.group.timeZone)
        return "\(self.dateText(domain.lowerBound)) – \(self.dateText(last)) · "
            + (start == end ? start : "\(start) → \(end)")
    }

    private func weekdayText(row: Int) -> String {
        guard self.model.weekdays.indices.contains(row) else { return "" }
        return SpendTrendChartModel.hourOfWeekWeekdayText(self.model.weekdays[row], calendar: self.calendar)
    }

    private func cellText(_ cell: HourOfWeekHeatmapModel.Cell) -> String {
        "\(self.weekdayText(row: cell.row)) \(SpendTrendChartModel.hourOfWeekClockText(cell.hour)) · "
            + self.costText(cell.cost)
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(
            locale: codexBarLocalizedLocale(),
            calendar: self.group.calendar,
            timeZone: self.group.timeZone).year().month(.abbreviated).day())
    }

    /// Same lower-bound marking as the trend chart: an isolated source uses its own completeness.
    private func costText(_ cost: Double) -> String {
        let source = self.sourceID.flatMap { id in self.group.providers.first { $0.id == id } }
        return spendDashboardMetricText(
            cost: cost,
            tokens: nil,
            currencyCode: self.group.currencyCode,
            costIsLowerBound: source.map { $0.costIsLowerBound || $0.incompleteRequestCount > 0 }
                ?? self.group.hasPartialCost)
    }
}
