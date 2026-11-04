import CodexBarCore
import SwiftUI

/// Insight tiles above the Usage & Spend summary: plan value, cache hit rate, cost per million
/// tokens and the top model's share of spend, each with a previous-period delta and a trend.
struct SpendInsightTilesRow: View {
    let group: SpendDashboardModel.CurrencyGroup
    /// Monthly plan price in the group's currency; `nil` until a plan price setting exists.
    let planMonthlyPrice: Double?

    var body: some View {
        let items = SpendInsightTileItem.items(
            for: SpendInsightTiles(
                inputs: self.group.insightInputs,
                calendar: self.group.calendar,
                planMonthlyPrice: self.planMonthlyPrice),
            currencyCode: self.group.currencyCode,
            planMonthlyPrice: self.planMonthlyPrice)
        if !items.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)],
                alignment: .leading,
                spacing: 12)
            {
                ForEach(items) { item in
                    SpendInsightTileView(item: item)
                }
            }
            .accessibilityIdentifier("spend-dashboard-insight-tiles")
        }
    }
}

// MARK: - Presentation

/// Display strings for one insight tile, kept apart from the view so they can be tested.
struct SpendInsightTileItem: Identifiable, Equatable {
    enum Kind: String {
        case planValue
        case cacheHitRate
        case costPerMillionTokens
        case topModelShare
    }

    let kind: Kind
    let title: String
    /// `nil` for the plan value hint, which has no number until a plan price is set.
    let value: String?
    let detail: String?
    let delta: String?
    let trend: [Double?]

    var id: Kind {
        self.kind
    }

    /// Tiles without a value are left out, except plan value, which asks for a plan price while
    /// there is spend to compare it with.
    static func items(
        for tiles: SpendInsightTiles,
        currencyCode: String,
        planMonthlyPrice: Double?) -> [SpendInsightTileItem]
    {
        var items: [SpendInsightTileItem] = []
        if let price = planMonthlyPrice, let tile = tiles.planValue {
            items.append(SpendInsightTileItem(
                kind: .planValue,
                title: L("Plan value"),
                value: spendInsightMultipleText(tile.value),
                detail: L(
                    "API-equivalent vs %@ plan",
                    UsageFormatter.currencyString(price, currencyCode: currencyCode)),
                delta: spendInsightDeltaText(tile.delta, style: .multiple),
                trend: tile.trend))
        } else if planMonthlyPrice == nil, tiles.apiEquivalentCost != nil {
            items.append(SpendInsightTileItem(
                kind: .planValue,
                title: L("Plan value"),
                value: nil,
                detail: L("Set a plan price to compare"),
                delta: nil,
                trend: []))
        }
        if let tile = tiles.cacheHitRate {
            items.append(SpendInsightTileItem(
                kind: .cacheHitRate,
                title: L("Cache hit rate"),
                value: spendInsightPercentText(tile.value),
                detail: nil,
                delta: spendInsightDeltaText(tile.delta, style: .points),
                trend: tile.trend))
        }
        if let tile = tiles.costPerMillionTokens {
            items.append(SpendInsightTileItem(
                kind: .costPerMillionTokens,
                title: L("Cost per 1M tokens"),
                value: UsageFormatter.currencyString(tile.value, currencyCode: currencyCode),
                detail: nil,
                delta: spendInsightDeltaText(tile.relativeDelta, style: .relative),
                trend: tile.trend))
        }
        if let share = tiles.topModelShare {
            items.append(SpendInsightTileItem(
                kind: .topModelShare,
                title: L("Top model share"),
                value: spendInsightPercentText(share.tile.value),
                detail: share.modelName,
                delta: spendInsightDeltaText(share.tile.delta, style: .points),
                trend: share.tile.trend))
        }
        return items
    }
}

enum SpendInsightDeltaStyle {
    /// Change relative to the previous value, as a percentage.
    case relative
    /// Change of a fraction, in percentage points.
    case points
    /// Change of a multiple, such as plan value.
    case multiple
}

/// "▲ 12% vs previous period". The text stays in a label color, so the arrow carries the direction.
func spendInsightDeltaText(_ change: Double?, style: SpendInsightDeltaStyle) -> String? {
    guard let change, change.isFinite else { return nil }
    let magnitude = abs(change)
    let text: String
    let roundsToZero: Bool
    switch style {
    case .relative:
        text = spendInsightPercentText(magnitude)
        roundsToZero = magnitude < 0.005
    case .points:
        text = L("%@ pts", spendInsightDecimalText(magnitude * 100, maximumFractionDigits: 1))
        roundsToZero = magnitude < 0.0005
    case .multiple:
        text = spendInsightMultipleText(magnitude)
        roundsToZero = magnitude < 0.05
    }
    let arrow = roundsToZero ? "" : change > 0 ? "▲ " : "▼ "
    return L("%@ vs previous period", arrow + text)
}

func spendInsightPercentText(_ fraction: Double) -> String {
    fraction.formatted(.percent.precision(.fractionLength(0)).locale(codexBarLocalizedLocale()))
}

func spendInsightMultipleText(_ value: Double) -> String {
    spendInsightDecimalText(value, maximumFractionDigits: value < 10 ? 1 : 0) + "×"
}

func spendInsightDecimalText(_ value: Double, maximumFractionDigits: Int) -> String {
    value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)).locale(codexBarLocalizedLocale()))
}

// MARK: - Tile

private struct SpendInsightTileView: View {
    let item: SpendInsightTileItem

    var body: some View {
        SpendDashboardPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.item.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let value = self.item.value {
                    Text(value)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if let detail = self.item.detail {
                    Text(detail)
                        .font(self.item.value == nil ? Font.callout : Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(self.item.value == nil ? 2 : 1)
                        .truncationMode(.middle)
                }
                if let delta = self.item.delta {
                    Text(delta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if self.item.trend.contains(where: { $0 != nil }) {
                    SpendInsightSparkline(values: self.item.trend)
                        .frame(height: 22)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spend-dashboard-insight-\(self.item.kind.rawValue)")
    }
}

// MARK: - Sparkline

/// A tiny trend line in the first palette slot. Gaps break the line; lone points draw as dots.
private struct SpendInsightSparkline: View {
    let values: [Double?]

    private static let color = ChartPalette.color(for: .index(0))

    var body: some View {
        GeometryReader { proxy in
            let segments = SpendInsightSparklineGeometry.segments(values: self.values, size: proxy.size)
            ZStack {
                Path { path in
                    for segment in segments where segment.count > 1 {
                        path.addLines(segment)
                    }
                }
                .stroke(Self.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                Path { path in
                    for point in SpendInsightSparklineGeometry.dots(in: segments) {
                        path.addEllipse(in: CGRect(x: point.x - 1.75, y: point.y - 1.75, width: 3.5, height: 3.5))
                    }
                }
                .fill(Self.color)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Sparkline layout, kept pure so gaps and flat trends can be tested.
enum SpendInsightSparklineGeometry {
    /// One point list per unbroken run of known values, scaled from the lowest to the highest value.
    static func segments(values: [Double?], size: CGSize, inset: CGFloat = 2) -> [[CGPoint]] {
        let known = values.compactMap(\.self).filter(\.isFinite)
        guard let minimum = known.min(), let maximum = known.max(), size.width > 0, size.height > 0 else {
            return []
        }
        let width = max(0, size.width - inset * 2)
        let height = max(0, size.height - inset * 2)
        let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0
        let span = maximum - minimum
        var segments: [[CGPoint]] = []
        var run: [CGPoint] = []
        for (index, entry) in values.enumerated() {
            guard let value = entry, value.isFinite else {
                if !run.isEmpty {
                    segments.append(run)
                    run = []
                }
                continue
            }
            // A flat trend sits on the middle line instead of hugging an edge.
            let fraction = span > 0 ? (value - minimum) / span : 0.5
            let x = values.count > 1 ? inset + CGFloat(index) * step : size.width / 2
            run.append(CGPoint(x: x, y: inset + height * (1 - CGFloat(fraction))))
        }
        if !run.isEmpty {
            segments.append(run)
        }
        return segments
    }

    /// Lone points, which a line cannot show, plus the latest point as an end marker.
    static func dots(in segments: [[CGPoint]]) -> [CGPoint] {
        var dots = segments.filter { $0.count == 1 }.compactMap(\.first)
        if let lastRun = segments.last, lastRun.count > 1, let last = lastRun.last {
            dots.append(last)
        }
        return dots
    }
}
