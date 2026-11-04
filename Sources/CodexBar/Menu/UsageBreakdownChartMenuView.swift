import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct UsageBreakdownChartMenuView: View {
    enum PresentationState: Equatable {
        case empty
        case totalsOnly
        case chart
    }

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let service: String
        let creditsUsed: Double

        init(date: Date, service: String, creditsUsed: Double) {
            self.date = date
            self.service = service
            self.creditsUsed = creditsUsed
            self.id = "\(service)-\(Int(date.timeIntervalSince1970))- \(creditsUsed)"
        }
    }

    private let breakdown: [OpenAIDashboardDailyBreakdown]
    private let now: Date
    private let calendar: Calendar
    private let width: CGFloat
    @State private var selectedDayKey: String?

    init(
        breakdown: [OpenAIDashboardDailyBreakdown],
        now: Date = Date(),
        calendar: Calendar = .current,
        width: CGFloat)
    {
        self.breakdown = breakdown
        self.now = now
        self.calendar = calendar
        self.width = width
    }

    var body: some View {
        let summary = OpenAIDashboardDailyBreakdown.recentUsageSummary(
            from: self.breakdown,
            now: self.now,
            calendar: self.calendar)
        let model = Self.makeModel(from: summary.daily)
        let presentationState = Self.presentationState(
            hasSummary: !summary.daily.isEmpty,
            hasChartPoints: !model.points.isEmpty)
        VStack(alignment: .leading, spacing: 10) {
            if presentationState != .empty {
                HStack(alignment: .firstTextBaseline) {
                    self.summaryMetric(title: L("Today"), credits: summary.todayCredits)
                    Spacer(minLength: 12)
                    self.summaryMetric(
                        title: String(format: L("Last %d days"), summary.historyDays),
                        credits: summary.totalCredits)
                }
            }

            if presentationState == .empty {
                Text(L("No usage breakdown data."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L("No usage breakdown data available."))
            } else if presentationState == .chart {
                Chart {
                    ForEach(model.points) { point in
                        BarMark(
                            x: .value(L("Day"), point.date, unit: .day),
                            y: .value(L("Credits used"), point.creditsUsed),
                            width: .ratio(ChartBarHoverSelection.barWidthRatio))
                            .foregroundStyle(by: .value(L("Service"), point.service))
                    }
                    if let average = model.dailyAverage {
                        RuleMark(y: .value(L("Daily average"), average))
                            .foregroundStyle(ChartReferenceLine.color)
                            .lineStyle(ChartReferenceLine.strokeStyle)
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                Text(String(
                                    format: L("avg %@ credits/day"),
                                    average.formatted(.number.precision(.fractionLength(0...2)))))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .chartForegroundStyleScale(domain: model.services, range: model.serviceColors)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: model.axisDates) { value in
                        AxisGridLine().foregroundStyle(Color.clear)
                        AxisTick().foregroundStyle(Color.clear)
                        if let date = value.as(Date.self) {
                            AxisValueLabel(anchor: ChartAxisLabelLayout.barCenteredAnchor) {
                                ChartAxisLabelLayout.dateLabel(
                                    Text(date, format: .dateTime.month(.abbreviated).day()))
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 130)
                .accessibilityLabel(L("Usage breakdown chart"))
                .accessibilityValue(
                    model.points.isEmpty
                        ? L("No data")
                        : String(
                            format: L("%d days of usage data across %d services"),
                            model.selectableDayDates.count,
                            model.services.count))
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            if let rect = self.selectionBandRect(model: model, proxy: proxy, geo: geo) {
                                Rectangle()
                                    .fill(Self.selectionBandColor)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .allowsHitTesting(false)
                            }
                            MouseLocationReader { location in
                                self.updateSelection(location: location, model: model, proxy: proxy, geo: geo)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        }
                    }
                }

                let detail = self.detailLines(model: model)
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.primary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 16, alignment: .leading)
                    Text(detail.secondary ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(height: 16, alignment: .leading)
                        .opacity(detail.secondary == nil ? 0 : 1)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
                    alignment: .leading,
                    spacing: 6)
                {
                    ForEach(model.services, id: \.self) { service in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(model.color(for: service))
                                .frame(width: 7, height: 7)
                            Text(service)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .leading)
    }

    static func presentationState(hasSummary: Bool, hasChartPoints: Bool) -> PresentationState {
        if hasChartPoints {
            return .chart
        }
        if hasSummary {
            return .totalsOnly
        }
        return .empty
    }

    static func _chartSeriesForTesting(breakdown: [OpenAIDashboardDailyBreakdown]) -> [String] {
        self.makeModel(from: breakdown).services
    }

    static func _dailyAverageForTesting(breakdown: [OpenAIDashboardDailyBreakdown]) -> Double? {
        self.makeModel(from: breakdown).dailyAverage
    }

    private struct Model {
        let points: [Point]
        let breakdownByDayKey: [String: OpenAIDashboardDailyBreakdown]
        let dayDates: [(dayKey: String, date: Date)]
        let selectableDayDates: [(dayKey: String, date: Date)]
        let dailyAverage: Double?
        let services: [String]
        let serviceColors: [Color]
        let axisDates: [Date]

        func color(for service: String) -> Color {
            guard let idx = self.services.firstIndex(of: service), idx < self.serviceColors.count else {
                return .secondary
            }
            return self.serviceColors[idx]
        }
    }

    private static let selectionBandColor = Color(nsColor: .labelColor).opacity(0.1)

    private func summaryMetric(title: String, credits: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Self.creditsString(credits))
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private static func creditsString(_ credits: Double?) -> String {
        guard let credits, credits.isFinite else { return "—" }
        let value = credits.formatted(.number.precision(.fractionLength(0...2)))
        return "\(value) \(L("credits"))"
    }

    private static func makeModel(from breakdown: [OpenAIDashboardDailyBreakdown]) -> Model {
        let sorted = OpenAIDashboardDailyBreakdown.removingSkillUsageServices(from: breakdown)
            .sorted { lhs, rhs in lhs.day < rhs.day }

        // Totals span the whole visible range, so hovering or selecting a day never reshuffles colors.
        let totals = Self.serviceTotals(from: sorted)
        let slots = Self.serviceSlots(totals: totals)
        let otherSeries = Self.otherSeriesName(avoiding: Set(slots.keys))

        var points: [Point] = []
        points.reserveCapacity(sorted.count * 2)

        var breakdownByDayKey: [String: OpenAIDashboardDailyBreakdown] = [:]
        breakdownByDayKey.reserveCapacity(sorted.count)

        var dayDates: [(dayKey: String, date: Date)] = []
        dayDates.reserveCapacity(sorted.count)

        var selectableDayDates: [(dayKey: String, date: Date)] = []
        selectableDayDates.reserveCapacity(sorted.count)

        var plottedDailyTotals: [Double] = []
        plottedDailyTotals.reserveCapacity(sorted.count)

        for day in sorted {
            guard let date = self.dateFromDayKey(day.day) else { continue }
            breakdownByDayKey[day.day] = day
            dayDates.append((dayKey: day.day, date: date))
            var plottedTotal: Double = 0
            var otherCredits: Double = 0
            for service in day.services where service.creditsUsed > 0 {
                plottedTotal += service.creditsUsed
                if slots[service.service] == .other {
                    otherCredits += service.creditsUsed
                } else {
                    points.append(Point(date: date, service: service.service, creditsUsed: service.creditsUsed))
                }
            }
            if otherCredits > 0 {
                points.append(Point(date: date, service: otherSeries, creditsUsed: otherCredits))
            }
            if plottedTotal > 0 {
                selectableDayDates.append((dayKey: day.day, date: date))
                plottedDailyTotals.append(plottedTotal)
            }
        }

        let ranked = ChartPalette.rankedNames(totals)
        var services = ranked.filter { slots[$0] != .other }
        var colors = services.map { ChartPalette.color(for: slots[$0] ?? .other) }
        if ranked.contains(where: { slots[$0] == .other }) {
            services.append(otherSeries)
            colors.append(ChartPalette.otherColor)
        }
        let axisDates = Self.axisDates(fromSortedDays: sorted)

        return Model(
            points: points,
            breakdownByDayKey: breakdownByDayKey,
            dayDates: dayDates,
            selectableDayDates: selectableDayDates,
            dailyAverage: ChartReferenceLine.dailyAverage(plottedDailyTotals),
            services: services,
            serviceColors: colors,
            axisDates: axisDates)
    }

    private static func serviceTotals(from breakdown: [OpenAIDashboardDailyBreakdown]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for day in breakdown {
            for service in day.services {
                totals[service.service, default: 0] += service.creditsUsed
            }
        }
        return totals
    }

    /// CLI keeps the first slot and GitHub code review the second; every other service fills the
    /// remaining slots by total, and services past the last slot fold into "Other".
    nonisolated static func serviceSlots(totals: [String: Double]) -> [String: ChartPalette.Slot] {
        ChartPalette.slotAssignment(
            for: totals.map { (name: $0.key, total: $0.value) },
            pinnedSlot: self.pinnedSlot(for:))
    }

    private nonisolated static func pinnedSlot(for service: String) -> Int? {
        let lower = service.lowercased()
        if lower == "cli" {
            return 0
        }
        if lower.contains("github"), lower.contains("review") {
            return 1
        }
        return nil
    }

    /// The overflow series label, kept distinct from real service names so the chart domain stays unique.
    private static func otherSeriesName(avoiding names: Set<String>) -> String {
        var label = L("Other")
        while names.contains(label) {
            label += " "
        }
        return label
    }

    private static func axisDates(fromSortedDays sortedDays: [OpenAIDashboardDailyBreakdown]) -> [Date] {
        guard let first = sortedDays.first, let last = sortedDays.last else { return [] }
        guard let firstDate = self.dateFromDayKey(first.day),
              let lastDate = self.dateFromDayKey(last.day)
        else {
            return []
        }
        if Calendar.current.isDate(firstDate, inSameDayAs: lastDate) {
            return [firstDate]
        }
        return [firstDate, lastDate]
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        // Noon avoids off-by-one-day shifts if anything ends up interpreted in UTC.
        comps.hour = 12
        return comps.date
    }

    private func selectionBandRect(model: Model, proxy: ChartProxy, geo: GeometryProxy) -> CGRect? {
        guard let key = self.selectedDayKey else { return nil }
        guard let index = model.selectableDayDates.firstIndex(where: { $0.dayKey == key }) else { return nil }
        guard let geometry = self.hoverGeometry(model: model, proxy: proxy, geo: geo) else { return nil }
        return geometry.bars[index].frame
    }

    private func updateSelection(
        location: CGPoint?,
        model: Model,
        proxy: ChartProxy,
        geo: GeometryProxy)
    {
        guard let location else {
            if self.selectedDayKey != nil {
                self.selectedDayKey = nil
            }
            return
        }

        guard let geometry = self.hoverGeometry(model: model, proxy: proxy, geo: geo),
              let selection = ChartBarHoverSelection.selection(
                  at: location,
                  plotFrame: geometry.plotFrame,
                  bars: geometry.bars)
        else { return }
        let key = model.selectableDayDates[selection.index].dayKey

        if self.selectedDayKey != key {
            self.selectedDayKey = key
        }
    }

    private func hoverGeometry(
        model: Model,
        proxy: ChartProxy,
        geo: GeometryProxy) -> (plotFrame: CGRect, bars: [ChartBarHoverSelection.Bar])?
    {
        guard let plotAnchor = proxy.plotFrame else { return nil }
        let plotFrame = geo[plotAnchor]
        guard let bars = ChartBarHoverSelection.calendarDayBars(
            dates: model.selectableDayDates.map(\.date),
            plotFrame: plotFrame,
            position: { proxy.position(forX: $0) })
        else { return nil }
        return (plotFrame, bars)
    }

    private func detailLines(model: Model) -> (primary: String, secondary: String?) {
        guard let key = self.selectedDayKey,
              let day = model.breakdownByDayKey[key],
              let date = Self.dateFromDayKey(key)
        else {
            return (L("Hover a bar for details"), nil)
        }

        let dayLabel = date.formatted(.dateTime.month(.abbreviated).day())
        let total = day.totalCreditsUsed.formatted(.number.precision(.fractionLength(0...2)))
        if day.services.isEmpty {
            return ("\(dayLabel): \(total)", nil)
        }
        if day.services.count <= 1, let first = day.services.first {
            let used = first.creditsUsed.formatted(.number.precision(.fractionLength(0...2)))
            return ("\(dayLabel): \(used)", first.service)
        }

        let services = day.services
            .sorted { lhs, rhs in
                if lhs.creditsUsed == rhs.creditsUsed {
                    return lhs.service < rhs.service
                }
                return lhs.creditsUsed > rhs.creditsUsed
            }
            .prefix(3)
            .map { "\($0.service) \($0.creditsUsed.formatted(.number.precision(.fractionLength(0...2))))" }
            .joined(separator: " · ")

        return ("\(dayLabel): \(total)", services)
    }
}
