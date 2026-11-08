import Foundation
import SharinganCore
import SwiftUI

/// Plan-fit pieces of `PlanUtilizationHistoryChartMenuView`'s model, computed once per series.
struct PlanFitChartParts {
    /// Slots the x domain spans: the window count, never fewer than `PlanFitChartLayout.minimumSlots`.
    let slotCount: Int
    let barWidth: CGFloat
    let cappedColor: Color
    /// Nil for quota observations, which have no reset cadence.
    let summary: PlanFit.Summary?
    /// Plan-fit windows keyed by the chart point id (the window's period boundary).
    let windowsByID: [Date: PlanFit.Window]
    /// Hours-until-reset labels drawn above capped bars, keyed by point index.
    let cappedLabelsByIndex: [Int: String]
    /// Most x-axis labels that fit the plot side by side.
    let axisLabelWidthBudget: Int
    /// Fewest slots between two x-axis labels so they do not overlap.
    let axisLabelMinimumSpacing: Int
}

/// Layout rules for the plan utilization chart. Pure, so tests cover them without rendering.
enum PlanFitChartLayout {
    /// Shorter histories sit at the trailing edge instead of stretching into a few very wide slots.
    static let minimumSlots = 8
    static let maxBarWidth: CGFloat = 14
    static let barSlotRatio: CGFloat = 0.6
    /// Narrowest gap between neighbouring bars, so a full history never reads as one solid block.
    static let minimumBarGap: CGFloat = 1
    /// Matches the chart view's horizontal padding.
    static let horizontalPadding: CGFloat = 16
    /// Room the leading 0/50/100% labels take from the plot.
    static let yAxisLabelReserve: CGFloat = 28
    /// Approximate caption widths of a session label ("Mar 4, 8 PM") and a day label ("Oct 26"), with a gap.
    static let sessionAxisLabelWidth: CGFloat = 64
    static let dayAxisLabelWidth: CGFloat = 40
    /// Capped-hours labels need about this much room per slot.
    static let cappedLabelMinimumSlotWidth: CGFloat = 14
    /// Headroom above the 100% cap leaves space for the capped-hours labels.
    static let yDomainTop: Double = 118
    static let yAxisTicks: [Double] = ChartNiceScale.ticks(maximum: 100, targetIntervals: 2)
    static let currentWindowOpacity: Double = 0.45
    static let footerSpacing: CGFloat = 2
    static let footerLineHeight: CGFloat = 16

    static func slotCount(pointCount: Int) -> Int {
        max(pointCount, self.minimumSlots)
    }

    /// Estimated plot width: the menu width minus padding, the y-axis labels and the x-axis edge padding.
    static func plotWidth(menuWidth: CGFloat) -> CGFloat {
        let reserved = 2 * self.horizontalPadding + self.yAxisLabelReserve
            + 2 * ChartAxisLabelLayout.dateLabelEdgePadding
        return max(1, menuWidth - reserved)
    }

    /// Bars take `barSlotRatio` of their slot, between `minimum` and `maxBarWidth`, but always leave
    /// `minimumBarGap` to the next bar: a full chart's slots are narrower than the minimum plus a gap.
    static func barWidth(slotCount: Int, plotWidth: CGFloat, minimum: CGFloat) -> CGFloat {
        let slotWidth = plotWidth / CGFloat(max(1, slotCount))
        let preferred = min(self.maxBarWidth, max(minimum, (slotWidth * self.barSlotRatio).rounded()))
        return max(1, min(preferred, (slotWidth - self.minimumBarGap).rounded(.down)))
    }

    /// Session (and observation) labels carry the hour, so they are wider than day labels.
    static func axisLabelWidth(windowMinutes: Int) -> CGFloat {
        windowMinutes <= PlanFit.sessionWindowMaxMinutes ? self.sessionAxisLabelWidth : self.dayAxisLabelWidth
    }

    static func axisLabelWidthBudget(plotWidth: CGFloat, labelWidth: CGFloat) -> Int {
        max(1, Int(floor(plotWidth / max(1, labelWidth))))
    }

    static func axisLabelMinimumSpacing(slotCount: Int, plotWidth: CGFloat, labelWidth: CGFloat) -> Int {
        let slotWidth = max(1, plotWidth / CGFloat(max(1, slotCount)))
        return max(1, Int(ceil(labelWidth / slotWidth)))
    }

    /// Keeps labels at least `minimumSpacing` slots apart, preferring the earlier label.
    static func spacedIndexes(_ indexes: [Int], minimumSpacing: Int) -> [Int] {
        var kept: [Int] = []
        for index in indexes {
            if let last = kept.last, index - last < minimumSpacing { continue }
            kept.append(index)
        }
        return kept
    }

    /// Drops trailing labels closer than `minimumSpacing` slots to `index`, so `index` can be labeled.
    static func indexes(_ indexes: [Int], makingRoomFor index: Int, minimumSpacing: Int) -> [Int] {
        var kept = indexes
        while let last = kept.last, index - last < minimumSpacing {
            kept.removeLast()
        }
        return kept
    }

    /// Capped bars that get an hours label: only when slots are wide enough, and never two side by side.
    static func labeledCappedIndexes(_ cappedIndexes: [Int], slotWidth: CGFloat) -> [Int] {
        guard slotWidth >= self.cappedLabelMinimumSlotWidth else { return [] }
        var labeled: [Int] = []
        for index in cappedIndexes.sorted() {
            if let last = labeled.last, index - last < 2 { continue }
            labeled.append(index)
        }
        return labeled
    }
}

/// Localized plan-fit copy and the capped-bar color.
enum PlanFitPresentation {
    /// Candidate `ChartPalette` slots for capped bars, in preference order: orange, then violet.
    static let cappedSlotCandidates = [1, 6]
    /// A candidate whose hue sits closer than this to the provider accent would blend into the regular bars.
    static let minimumCappedHueDistance: Double = 40

    // MARK: - Copy

    /// "Median 62% · capped 2 of 12 weeks · 9 h capped"; nil until a window has settled.
    static func summaryLine(_ summary: PlanFit.Summary) -> String? {
        guard summary.settledWindowCount > 0 else { return nil }
        var segments: [String] = []
        if let median = summary.medianPeakPercent {
            segments.append(self.medianText(median))
        }
        let capped = summary.cappedWindowCount
        let total = summary.settledWindowCount
        switch summary.cadence {
        case .session:
            segments.append(L(
                "%@ capped sessions per week",
                self.decimalText(summary.cappedSessionsPerWeek ?? 0)))
        case .weekly:
            segments.append(L("capped %d of %d weeks", capped, total))
        case .monthly:
            segments.append(L("capped %d of %d months", capped, total))
        case .other:
            segments.append(L("capped %d of %d windows", capped, total))
        }
        if summary.cappedHours > 0 {
            segments.append(self.cappedHoursText(summary.cappedHours))
        }
        return segments.joined(separator: " · ")
    }

    static func verdictLine(_ verdict: PlanFit.Verdict) -> String {
        switch verdict {
        case .notEnoughHistory:
            L("Not enough history for a verdict yet.")
        case .underused:
            L("You may be paying for headroom you don't use.")
        case .hitsCapOften:
            L("You hit the cap often.")
        case .fits:
            L("Your plan fits how you use it.")
        }
    }

    static func medianText(_ percent: Double) -> String {
        L("Median %@%%", sharinganLocalizedInteger(Int(percent.clamped(to: 0...100).rounded())))
    }

    static func cappedHoursText(_ hours: Double) -> String {
        L("%@ h capped", self.hoursText(hours))
    }

    /// The short label above a capped bar: hours from hitting the cap to the reset.
    static func cappedBarLabel(hours: Double) -> String {
        L("%@h", self.hoursText(hours))
    }

    static func percentAxisLabel(_ percent: Double) -> String {
        "\(sharinganLocalizedInteger(Int(percent.rounded())))%"
    }

    static func hoursText(_ hours: Double) -> String {
        let locale = sharinganLocalizedLocale()
        if hours < 10 {
            return hours.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        }
        return hours.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    private static func decimalText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(sharinganLocalizedLocale()))
    }

    // MARK: - Color

    /// Orange by default; violet when the provider accent is itself orange or red, so capped bars stay distinct.
    static func cappedSlot(accent: ProviderColor) -> ChartPalette.Slot {
        guard let accentHue = self.hueDegrees(red: accent.red, green: accent.green, blue: accent.blue) else {
            return .index(self.cappedSlotCandidates[0])
        }
        var best: (slot: Int, distance: Double)?
        for slot in self.cappedSlotCandidates where ChartPalette.swatches.indices.contains(slot) {
            guard let hue = self.hueDegrees(hex: ChartPalette.swatches[slot].light) else { continue }
            let distance = self.hueDistance(accentHue, hue)
            if distance >= self.minimumCappedHueDistance {
                return .index(slot)
            }
            if best.map({ distance > $0.distance }) ?? true {
                best = (slot, distance)
            }
        }
        return best.map { ChartPalette.Slot.index($0.slot) } ?? .other
    }

    /// Hue in degrees (0..<360), or nil for near-gray colors whose hue is not meaningful.
    static func hueDegrees(red: Double, green: Double, blue: Double) -> Double? {
        let maxComponent = max(red, green, blue)
        let chroma = maxComponent - min(red, green, blue)
        guard chroma > 0.1 else { return nil }
        let sector: Double = if maxComponent == red {
            (green - blue) / chroma
        } else if maxComponent == green {
            (blue - red) / chroma + 2
        } else {
            (red - green) / chroma + 4
        }
        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func hueDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private static func hueDegrees(hex: UInt32) -> Double? {
        self.hueDegrees(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
