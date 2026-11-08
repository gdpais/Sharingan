import SharinganCore
import Testing
@testable import Sharingan

@Suite("Chart palette")
struct ChartPaletteTests {
    private static func totals(_ count: Int) -> [(name: String, total: Double)] {
        (0..<count).map { (name: "service-\($0)", total: Double(100 - $0)) }
    }

    // MARK: - Slot assignment

    @Test
    func `assignment is the same for any input order`() {
        let input: [(name: String, total: Double)] = [
            (name: "beta", total: 5),
            (name: "alpha", total: 5),
            (name: "gamma", total: 9),
            (name: "delta", total: 1),
        ]
        let expected = ChartPalette.slotAssignment(for: input)
        #expect(ChartPalette.slotAssignment(for: Array(input.reversed())) == expected)
        #expect(ChartPalette.slotAssignment(for: input.sorted { $0.name < $1.name }) == expected)
        #expect(expected == [
            "gamma": .index(0),
            "alpha": .index(1),
            "beta": .index(2),
            "delta": .index(3),
        ])
    }

    @Test
    func `up to eight series never share a slot`() {
        for count in 1...ChartPalette.slotCount {
            let assignment = ChartPalette.slotAssignment(for: Self.totals(count))
            let slots = Set(assignment.values)
            #expect(slots.count == count)
            #expect(!slots.contains(.other))
        }
    }

    @Test
    func `pinned series keep their slot and the rest fill the free slots`() {
        let assignment = ChartPalette.slotAssignment(
            for: [
                (name: "big", total: 100),
                (name: "pinned", total: 1),
                (name: "mid", total: 50),
            ],
            pinnedSlot: { $0 == "pinned" ? 0 : nil })
        #expect(assignment == [
            "pinned": .index(0),
            "big": .index(1),
            "mid": .index(2),
        ])
    }

    @Test
    func `the higher ranked series wins a contested pin`() {
        let assignment = ChartPalette.slotAssignment(
            for: [
                (name: "small", total: 1),
                (name: "large", total: 10),
            ],
            pinnedSlot: { _ in 0 })
        #expect(assignment == ["large": .index(0), "small": .index(1)])
    }

    @Test
    func `series past the last slot fold into other`() {
        let assignment = ChartPalette.slotAssignment(for: Self.totals(ChartPalette.slotCount + 3))
        let named = assignment.filter { $0.value != .other }
        #expect(named.count == ChartPalette.slotCount)
        #expect(assignment["service-8"] == .other)
        #expect(assignment["service-10"] == .other)
        #expect(assignment["service-0"] == .index(0))
    }

    @Test
    func `duplicate names are summed and non finite totals rank as zero`() {
        let assignment = ChartPalette.slotAssignment(for: [
            (name: "split", total: 3),
            (name: "whole", total: 5),
            (name: "split", total: 3),
            (name: "broken", total: .nan),
        ])
        #expect(assignment == ["split": .index(0), "whole": .index(1), "broken": .index(2)])
    }

    // MARK: - Daily average

    @Test
    func `daily average only counts days with data`() {
        #expect(ChartReferenceLine.dailyAverage([0, 4, 0, 8, .nan]) == 6)
        #expect(ChartReferenceLine.dailyAverage([0, 0]) == nil)
        #expect(ChartReferenceLine.dailyAverage([]) == nil)
    }

    // MARK: - Chart wiring

    @Test
    @MainActor
    func `usage breakdown pins cli and github review ahead of larger services`() {
        let slots = UsageBreakdownChartMenuView.serviceSlots(totals: [
            "Web": 90,
            "GitHub Code Review": 2,
            "CLI": 1,
            "Desktop": 40,
        ])
        #expect(slots == [
            "CLI": .index(0),
            "GitHub Code Review": .index(1),
            "Web": .index(2),
            "Desktop": .index(3),
        ])
    }

    @Test
    @MainActor
    func `usage breakdown aggregates overflow services into one other series`() {
        let services = (0..<10).map {
            OpenAIDashboardServiceUsage(service: "service-\($0)", creditsUsed: Double(20 - $0))
        }
        let total = services.reduce(0) { $0 + $1.creditsUsed }
        let breakdown = [
            OpenAIDashboardDailyBreakdown(day: "2026-01-02", services: services, totalCreditsUsed: total),
        ]
        let series = UsageBreakdownChartMenuView._chartSeriesForTesting(breakdown: breakdown)
        #expect(series.count == ChartPalette.slotCount + 1)
        #expect(series.last == L("Other"))
        #expect(!series.contains("service-8"))
        #expect(!series.contains("service-9"))
    }

    @Test
    @MainActor
    func `chart averages ignore empty days`() {
        let breakdown = [
            OpenAIDashboardDailyBreakdown(
                day: "2026-01-01",
                services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 2)],
                totalCreditsUsed: 2),
            OpenAIDashboardDailyBreakdown(day: "2026-01-02", services: [], totalCreditsUsed: 0),
            OpenAIDashboardDailyBreakdown(
                day: "2026-01-03",
                services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 6)],
                totalCreditsUsed: 6),
        ]
        #expect(UsageBreakdownChartMenuView._dailyAverageForTesting(breakdown: breakdown) == 4)
        #expect(CreditsHistoryChartMenuView._dailyAverageForTesting(breakdown: breakdown) == 4)
    }
}
