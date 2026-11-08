import Charts
import SharinganCore
import SwiftUI

/// Fixed-height runway chart for a prepaid balance: the observed balance and a dashed projection to zero.
@MainActor
struct BalanceRunwayChartMenuView: View {
    struct Display: Equatable {
        /// Currency amounts are formatted in; nil for provider units such as credits or points.
        let currencyCode: String?
        /// Converts the provider's unit into `currencyCode`.
        let multiplier: Double

        static let providerUnits = Self(currencyCode: nil, multiplier: 1)
    }

    static let chartHeight: CGFloat = 110
    /// The row is sized from this constant, never measured, so the menu needs no layout pass for it.
    static let preferredHeight: CGFloat = 226

    private static let lineColor = ChartPalette.color(for: .index(0))

    private let model: BalanceRunwayChartModel
    private let display: Display
    private let width: CGFloat
    private let yTicks: [Double]

    init(model: BalanceRunwayChartModel, display: Display, width: CGFloat) {
        self.model = model
        self.display = display
        self.width = width
        self.yTicks = ChartNiceScale.ticks(maximum: Self.displayed(model.maximumBalance, display: display))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Balance"))
                    .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold))
                Spacer(minLength: 8)
                Text(Self.amountText(self.model.estimate.currentBalance, display: self.display))
                    .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize).monospacedDigit())
            }
            .lineLimit(1)

            self.chart

            HStack {
                Text(Self.dateText(self.model.domainStart, relativeTo: self.model.estimate.observedAt))
                Spacer(minLength: 8)
                Text(Self.dateText(self.model.domainEnd, relativeTo: self.model.estimate.observedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text(L("avg %@/day", Self.amountText(self.model.estimate.burnPerDay, display: self.display)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Self.lastsUntilText(
                self.model.estimate.depletionDate,
                relativeTo: self.model.estimate.observedAt))
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: self.width, height: Self.preferredHeight, alignment: .topLeading)
        .sharinganLocalized()
    }

    private var chart: some View {
        Chart {
            ForEach(self.model.history, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(L("Balance"), Self.displayed(point.balance, display: self.display)),
                    series: .value("Series", "Observed"))
                    .foregroundStyle(Self.lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(self.model.projection, id: \.date) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(L("Balance"), Self.displayed(point.balance, display: self.display)),
                    series: .value("Series", "Projection"))
                    .foregroundStyle(Self.lineColor)
                    .lineStyle(ChartReferenceLine.strokeStyle)
            }
            if let current = self.model.history.last {
                PointMark(
                    x: .value("Time", current.date),
                    y: .value(L("Balance"), Self.displayed(current.balance, display: self.display)))
                    .foregroundStyle(Self.lineColor)
                    .symbolSize(30)
            }
            if self.model.projectionReachesZero, let empty = self.model.projection.last {
                PointMark(
                    x: .value("Time", empty.date),
                    y: .value(L("Balance"), 0.0))
                    .foregroundStyle(Self.lineColor)
                    .symbolSize(24)
            }
        }
        .chartXScale(domain: self.model.domainStart...self.model.domainEnd)
        .chartYScale(domain: 0...self.yDomainMaximum)
        .chartYAxis {
            AxisMarks(position: .leading, values: self.yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(nsColor: .separatorColor))
                AxisTick().foregroundStyle(Color.clear)
                AxisValueLabel(centered: false) {
                    if let raw = value.as(Double.self) {
                        Text(Self.axisText(raw, display: self.display))
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            .padding(.leading, 4)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: Self.chartHeight)
        .accessibilityLabel(L("Balance"))
        .accessibilityValue(Self.lastsUntilText(
            self.model.estimate.depletionDate,
            relativeTo: self.model.estimate.observedAt))
    }

    private var yDomainMaximum: Double {
        self.yTicks.last ?? max(Self.displayed(self.model.maximumBalance, display: self.display), 1)
    }

    // MARK: - Formatting

    static func lastsUntilText(_ date: Date, relativeTo reference: Date) -> String {
        L("Lasts until %@ at this rate", self.dateText(date, relativeTo: reference))
    }

    /// Month and day, plus the year when it differs from the reference date's year.
    static func dateText(_ date: Date, relativeTo reference: Date, calendar: Calendar = .current) -> String {
        let locale = sharinganLocalizedLocale()
        if calendar.component(.year, from: date) == calendar.component(.year, from: reference) {
            return date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }

    static func amountText(_ value: Double, display: Display) -> String {
        let shown = self.displayed(value, display: display)
        guard let currencyCode = display.currencyCode else {
            return UsageFormatter.creditsNumberString(from: shown)
        }
        return UsageFormatter.currencyString(shown, currencyCode: currencyCode)
    }

    private static func axisText(_ value: Double, display: Display) -> String {
        guard let currencyCode = display.currencyCode else {
            return UsageFormatter.creditsNumberString(from: value)
        }
        return UsageFormatter.compactCurrencyString(value, currencyCode: currencyCode)
    }

    private static func displayed(_ value: Double, display: Display) -> Double {
        let shown = value * display.multiplier
        return shown.isFinite ? shown : value
    }
}
