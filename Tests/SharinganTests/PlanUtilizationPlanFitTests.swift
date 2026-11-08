import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

struct PlanUtilizationPlanFitTests {
    // MARK: - Layout

    @Test
    func `slot count fits the windows with a floor of eight`() {
        #expect(PlanFitChartLayout.slotCount(pointCount: 0) == 8)
        #expect(PlanFitChartLayout.slotCount(pointCount: 3) == 8)
        #expect(PlanFitChartLayout.slotCount(pointCount: 12) == 12)
        #expect(PlanFitChartLayout.slotCount(pointCount: 30) == 30)
    }

    @Test
    func `bars widen with the slots but stay between the minimum and maximum`() {
        let plotWidth = PlanFitChartLayout.plotWidth(menuWidth: 310)
        #expect(plotWidth == 186)
        #expect(PlanFitChartLayout.barWidth(slotCount: 12, plotWidth: plotWidth, minimum: 6) == 9)
        #expect(PlanFitChartLayout.barWidth(slotCount: 8, plotWidth: plotWidth, minimum: 6) == 14)
        #expect(PlanFitChartLayout.barWidth(slotCount: 1, plotWidth: plotWidth, minimum: 6) == 14)
    }

    @Test
    func `a full history keeps a gap between bars below the minimum width`() {
        let plotWidth = PlanFitChartLayout.plotWidth(menuWidth: 310)
        // 30 slots of 6.2 points: the 6-point minimum would leave bars almost touching.
        let full = PlanFitChartLayout.barWidth(slotCount: 30, plotWidth: plotWidth, minimum: 6)
        #expect(full == 5)
        #expect(plotWidth / 30 - full >= PlanFitChartLayout.minimumBarGap)
        #expect(PlanFitChartLayout.barWidth(slotCount: 30, plotWidth: 1, minimum: 6) == 1)
    }

    @Test
    func `y axis ticks are zero fifty and one hundred percent`() {
        #expect(PlanFitChartLayout.yAxisTicks == [0, 50, 100])
        #expect(PlanFitChartLayout.yDomainTop > 100)
    }

    @Test
    func `axis label spacing follows the label width and slot width`() {
        let session = PlanFitChartLayout.axisLabelWidth(windowMinutes: 300)
        let weekly = PlanFitChartLayout.axisLabelWidth(windowMinutes: 10080)
        #expect(session > weekly)
        #expect(PlanFitChartLayout.axisLabelWidthBudget(plotWidth: 186, labelWidth: session) == 2)
        #expect(PlanFitChartLayout.axisLabelWidthBudget(plotWidth: 186, labelWidth: weekly) == 4)
        #expect(PlanFitChartLayout.axisLabelMinimumSpacing(slotCount: 15, plotWidth: 186, labelWidth: session) == 6)
        #expect(PlanFitChartLayout.axisLabelMinimumSpacing(slotCount: 12, plotWidth: 186, labelWidth: weekly) == 3)
    }

    @Test
    func `spaced indexes keep the earlier label and drop crowded ones`() {
        #expect(PlanFitChartLayout.spacedIndexes([0, 1, 6, 10], minimumSpacing: 6) == [0, 6])
        #expect(PlanFitChartLayout.spacedIndexes([0, 10], minimumSpacing: 6) == [0, 10])
        #expect(PlanFitChartLayout.spacedIndexes([], minimumSpacing: 3).isEmpty)
    }

    @Test
    func `making room for the newest label drops only labels too close to it`() {
        #expect(PlanFitChartLayout.indexes([0, 15, 25], makingRoomFor: 29, minimumSpacing: 11) == [0, 15])
        #expect(PlanFitChartLayout.indexes([0, 10, 19], makingRoomFor: 29, minimumSpacing: 6) == [0, 10, 19])
        #expect(PlanFitChartLayout.indexes([25], makingRoomFor: 29, minimumSpacing: 11).isEmpty)
    }

    @Test
    func `capped labels skip neighbours and narrow slots`() {
        #expect(PlanFitChartLayout.labeledCappedIndexes([3, 1, 2, 6], slotWidth: 15) == [1, 3, 6])
        #expect(PlanFitChartLayout.labeledCappedIndexes([1, 5], slotWidth: 10).isEmpty)
    }

    // MARK: - Color

    @Test
    func `capped bars use orange unless the provider accent is orange or red`() {
        let codexTeal = ProviderColor(red: 73 / 255, green: 163 / 255, blue: 176 / 255)
        let claudeOrange = ProviderColor(red: 204 / 255, green: 124 / 255, blue: 94 / 255)
        let red = ProviderColor(red: 0.9, green: 0.2, blue: 0.2)
        let gray = ProviderColor(red: 0.5, green: 0.5, blue: 0.5)
        #expect(PlanFitPresentation.cappedSlot(accent: codexTeal) == .index(1))
        #expect(PlanFitPresentation.cappedSlot(accent: claudeOrange) == .index(6))
        #expect(PlanFitPresentation.cappedSlot(accent: red) == .index(6))
        #expect(PlanFitPresentation.cappedSlot(accent: gray) == .index(1))
    }

    @Test
    func `hue math wraps around the color wheel`() {
        #expect(PlanFitPresentation.hueDegrees(red: 1, green: 0, blue: 0) == 0)
        #expect(PlanFitPresentation.hueDegrees(red: 0, green: 1, blue: 0) == 120)
        #expect(PlanFitPresentation.hueDegrees(red: 0, green: 0, blue: 1) == 240)
        #expect(PlanFitPresentation.hueDegrees(red: 1, green: 0, blue: 0.5) == 330)
        #expect(PlanFitPresentation.hueDegrees(red: 0.5, green: 0.52, blue: 0.5) == nil)
        #expect(PlanFitPresentation.hueDistance(350, 10) == 20)
        #expect(PlanFitPresentation.hueDistance(10, 200) == 170)
    }

    // MARK: - Copy

    @Test
    func `summary line names months for monthly windows and skips zero hours`() {
        let month: TimeInterval = 30 * 24 * 60 * 60
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let inputs = [20.0, 40, 30, 50, 60].enumerated().map { index, peak in
            let reset = start.addingTimeInterval(Double(index) * month)
            return PlanFit.WindowInput(
                resetsAt: reset,
                captures: [PlanFit.Capture(capturedAt: reset.addingTimeInterval(-3600), usedPercent: peak)])
        }
        let summary = PlanFit.summary(
            windows: inputs,
            windowMinutes: 43200,
            now: start.addingTimeInterval(10 * month))

        #expect(PlanFitPresentation.summaryLine(summary) == "Median 40% · capped 0 of 5 months")
        #expect(PlanFitPresentation.verdictLine(summary.verdict) == "Your plan fits how you use it.")
    }

    @Test
    func `summary line is empty until a window settles`() {
        let start = Date(timeIntervalSince1970: 1_710_000_000)
        let running = PlanFit.WindowInput(
            resetsAt: start,
            captures: [PlanFit.Capture(capturedAt: start.addingTimeInterval(-3600), usedPercent: 20)])
        let summary = PlanFit.summary(
            windows: [running],
            windowMinutes: 10080,
            now: start.addingTimeInterval(-60))

        #expect(PlanFitPresentation.summaryLine(summary) == nil)
        #expect(PlanFitPresentation.verdictLine(summary.verdict) == "Not enough history for a verdict yet.")
    }

    @Test
    func `verdict copy covers every verdict`() {
        #expect(PlanFitPresentation.verdictLine(.underused) == "You may be paying for headroom you don't use.")
        #expect(PlanFitPresentation.verdictLine(.hitsCapOften) == "You hit the cap often.")
        #expect(PlanFitPresentation.verdictLine(.fits) == "Your plan fits how you use it.")
        #expect(PlanFitPresentation.verdictLine(.notEnoughHistory) == "Not enough history for a verdict yet.")
    }

    @Test
    func `hours keep one decimal below ten and none above`() {
        #expect(PlanFitPresentation.cappedBarLabel(hours: 9) == "9h")
        #expect(PlanFitPresentation.cappedBarLabel(hours: 2.5) == "2.5h")
        #expect(PlanFitPresentation.cappedHoursText(12.4) == "12 h capped")
        #expect(PlanFitPresentation.percentAxisLabel(50) == "50%")
        #expect(PlanFitPresentation.medianText(61.6) == "Median 62%")
    }
}
