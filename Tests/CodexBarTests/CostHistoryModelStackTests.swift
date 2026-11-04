import CodexBarCore
import Foundation
import Testing

struct CostHistoryModelStackTests {
    private typealias Stack = CostHistoryModelStack
    private typealias Entry = CostUsageDailyReport.Entry
    private typealias Model = CostUsageDailyReport.ModelBreakdown

    // MARK: - Top models

    @Test
    func `top two models come from the whole range total, not one day`() {
        let entries = [
            Self.entry("2026-06-01", cost: 10, models: [
                Model(modelName: "fixture-alpha", costUSD: 9),
                Model(modelName: "fixture-beta", costUSD: 1),
            ]),
            Self.entry("2026-06-02", cost: 10, models: [
                Model(modelName: "fixture-beta", costUSD: 6),
                Model(modelName: "fixture-gamma", costUSD: 4),
            ]),
            Self.entry("2026-06-03", cost: 5, models: [
                Model(modelName: "fixture-gamma", costUSD: 5),
            ]),
        ]
        // alpha 9, beta 7, gamma 9: alpha and gamma tie, and the tie breaks by name.
        #expect(Stack.topModels(entries, metric: .cost) == ["fixture-alpha", "fixture-gamma"])
        #expect(Stack.topModels(entries, metric: .cost, limit: 3)
            == ["fixture-alpha", "fixture-gamma", "fixture-beta"])
    }

    @Test
    func `top model selection is deterministic regardless of entry and breakdown order`() {
        let models = (0..<6).map { Model(modelName: "fixture-\($0)", costUSD: 2) }
        let forward = [Self.entry("2026-06-01", cost: 12, models: models)]
        let reversed = [Self.entry("2026-06-01", cost: 12, models: Array(models.reversed()))]
        #expect(Stack.topModels(forward, metric: .cost) == ["fixture-0", "fixture-1"])
        #expect(Stack.topModels(reversed, metric: .cost) == ["fixture-0", "fixture-1"])
    }

    @Test
    func `blank names and models without a positive total never take a slot`() {
        let entries = [
            Self.entry("2026-06-01", cost: 3, models: [
                Model(modelName: "  ", costUSD: 50),
                Model(modelName: " fixture-alpha ", costUSD: 3),
                Model(modelName: "fixture-free", costUSD: 0),
                Model(modelName: "fixture-unpriced", costUSD: nil),
                Model(modelName: "fixture-broken", costUSD: .nan),
            ]),
        ]
        #expect(Stack.topModels(entries, metric: .cost) == ["fixture-alpha"])
    }

    @Test
    func `token metric ranks by tokens instead of cost`() {
        let entries = [
            Self.entry("2026-06-01", cost: 10, tokens: 1000, models: [
                Model(modelName: "fixture-pricey", costUSD: 9, totalTokens: 100),
                Model(modelName: "fixture-chatty", costUSD: 1, totalTokens: 900),
            ]),
        ]
        #expect(Stack.topModels(entries, metric: .cost) == ["fixture-pricey", "fixture-chatty"])
        #expect(Stack.topModels(entries, metric: .tokens) == ["fixture-chatty", "fixture-pricey"])
    }

    // MARK: - Segments

    @Test
    func `segments stack the top models bottom up and fold the rest into other`() {
        let entry = Self.entry("2026-06-01", cost: 10, models: [
            Model(modelName: "fixture-gamma", costUSD: 1),
            Model(modelName: "fixture-alpha", costUSD: 5),
            Model(modelName: "fixture-beta", costUSD: 3),
            Model(modelName: "fixture-delta", costUSD: 1),
        ])
        let segments = Stack.segments(
            for: entry,
            total: 10,
            topModels: ["fixture-alpha", "fixture-beta"],
            metric: .cost)
        #expect(segments == [
            Stack.Segment(series: .model(0), start: 0, end: 5),
            Stack.Segment(series: .model(1), start: 5, end: 8),
            Stack.Segment(series: .other, start: 8, end: 10),
        ])
    }

    @Test
    func `segments always end at the day total`() {
        let overshoot = Self.entry("2026-06-01", cost: 4, models: [
            Model(modelName: "fixture-alpha", costUSD: 3),
            Model(modelName: "fixture-beta", costUSD: 3),
        ])
        let clamped = Stack.segments(
            for: overshoot,
            total: 4,
            topModels: ["fixture-alpha", "fixture-beta"],
            metric: .cost)
        #expect(clamped == [
            Stack.Segment(series: .model(0), start: 0, end: 3),
            Stack.Segment(series: .model(1), start: 3, end: 4),
        ])

        // Unattributed spend is part of "everything else".
        let undershoot = Self.entry("2026-06-02", cost: 10, models: [
            Model(modelName: "fixture-alpha", costUSD: 4),
        ])
        let remainder = Stack.segments(for: undershoot, total: 10, topModels: ["fixture-alpha"], metric: .cost)
        #expect(remainder == [
            Stack.Segment(series: .model(0), start: 0, end: 4),
            Stack.Segment(series: .other, start: 4, end: 10),
        ])
    }

    @Test
    func `rounding noise does not create an other sliver`() {
        let entry = Self.entry("2026-06-01", cost: 0.3, models: [
            Model(modelName: "fixture-alpha", costUSD: 0.1),
            Model(modelName: "fixture-beta", costUSD: 0.2),
        ])
        let segments = Stack.segments(
            for: entry,
            total: 0.3,
            topModels: ["fixture-alpha", "fixture-beta"],
            metric: .cost)
        #expect(segments.map(\.series) == [.model(0), .model(1)])
        #expect(segments.last?.end == 0.3)
    }

    @Test
    func `a day without the top models is all other`() {
        let entry = Self.entry("2026-06-01", cost: 2, models: [Model(modelName: "fixture-delta", costUSD: 2)])
        let segments = Stack.segments(for: entry, total: 2, topModels: ["fixture-alpha"], metric: .cost)
        #expect(segments == [Stack.Segment(series: .other, start: 0, end: 2)])
    }

    @Test
    func `days without a breakdown or a positive total are left unstacked`() {
        let missing = Self.entry("2026-06-01", cost: 2, models: nil)
        let empty = Self.entry("2026-06-02", cost: 2, models: [])
        let zero = Self.entry("2026-06-03", cost: 0, models: [Model(modelName: "fixture-alpha", costUSD: 0)])
        for entry in [missing, empty, zero] {
            let segments = Stack.segments(
                for: entry,
                total: entry.costUSD ?? 0,
                topModels: ["fixture-alpha"],
                metric: .cost)
            #expect(segments.isEmpty)
        }
        #expect(Stack.segments(for: missing, total: 2, topModels: [], metric: .cost).isEmpty)
    }

    // MARK: - Stack

    @Test
    func `stack keys segments by day and reports other`() throws {
        let first = Self.entry("2026-06-01", cost: 6, models: [
            Model(modelName: "fixture-alpha", costUSD: 4),
            Model(modelName: "fixture-beta", costUSD: 1),
            Model(modelName: "fixture-gamma", costUSD: 1),
        ])
        let plain = Self.entry("2026-06-02", cost: 3, models: nil)
        let bars: [(entry: Entry, total: Double)] = [(entry: first, total: 6), (entry: plain, total: 3)]
        let stack = try #require(Stack.stack(bars, metric: .cost))
        #expect(stack.models == ["fixture-alpha", "fixture-beta"])
        #expect(Array(stack.segmentsByDayKey.keys) == ["2026-06-01"])
        #expect(stack.hasOther)
    }

    @Test
    func `stack is nil when nothing can be stacked`() {
        let plain = Self.entry("2026-06-01", cost: 3, models: nil)
        let unpriced = Self.entry("2026-06-02", cost: 3, models: [Model(modelName: "fixture-alpha", costUSD: nil)])
        let bars: [(entry: Entry, total: Double)] = [(entry: plain, total: 3), (entry: unpriced, total: 3)]
        #expect(Stack.stack(bars, metric: .cost) == nil)
        #expect(Stack.stack([], metric: .tokens) == nil)
    }

    // MARK: - Previous period

    @Test
    func `period delta is the fractional change against the previous period`() throws {
        let growth = try #require(Stack.periodDelta(currentTotal: 112, previousPeriodTotal: 100, days: 30))
        #expect(abs(growth - 0.12) < 1e-12)
        #expect(Stack.periodDelta(currentTotal: 50, previousPeriodTotal: 100, days: 30) == -0.5)
        #expect(Stack.periodDelta(currentTotal: 0, previousPeriodTotal: 100, days: 30) == -1)
        #expect(Stack.periodDelta(currentTotal: 100, previousPeriodTotal: 100, days: 7) == 0)
    }

    @Test
    func `period delta is hidden without a meaningful previous period`() {
        // Growth from nothing has no percentage.
        #expect(Stack.periodDelta(currentTotal: 10, previousPeriodTotal: 0, days: 30) == nil)
        #expect(Stack.periodDelta(currentTotal: 10, previousPeriodTotal: nil, days: 30) == nil)
        #expect(Stack.periodDelta(currentTotal: nil, previousPeriodTotal: 10, days: 30) == nil)
        #expect(Stack.periodDelta(currentTotal: 10, previousPeriodTotal: -5, days: 30) == nil)
        #expect(Stack.periodDelta(currentTotal: .nan, previousPeriodTotal: 10, days: 30) == nil)
        #expect(Stack.periodDelta(currentTotal: 10, previousPeriodTotal: .infinity, days: 30) == nil)
        // A partial today dominates windows shorter than a week.
        #expect(Stack.periodDelta(currentTotal: 10, previousPeriodTotal: 5, days: 6) == nil)
    }

    @Test
    func `previous period total sums the equal window before the current one`() throws {
        let calendar = Self.utcCalendar
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        // May 31 sits before both windows, June is the previous period and July the current one.
        let entries = (0..<61).compactMap { offset -> Entry? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let components = calendar.dateComponents([.month], from: day)
            let cost: Double = switch components.month ?? 0 {
            case 5: 100
            case 6: 1
            default: 2
            }
            return Self.entry(Self.dayKey(day, calendar: calendar), cost: cost, models: nil)
        }
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12)))
        #expect(Stack.previousPeriodTotal(entries, days: 30, now: now, metric: .cost, calendar: calendar) == 30)
        #expect(Stack.previousPeriodTotal(entries, days: 30, now: now, metric: .tokens, calendar: calendar) == nil)
        #expect(Stack.previousPeriodTotal(entries, days: 0, now: now, metric: .cost, calendar: calendar) == nil)
        let currentOnly = entries.filter { $0.date >= "2026-07-01" }
        #expect(Stack.previousPeriodTotal(currentOnly, days: 30, now: now, metric: .cost, calendar: calendar) == nil)
    }

    // MARK: - Weekends

    @Test
    func `weekend intervals merge saturday and sunday into one run`() throws {
        let calendar = Self.utcCalendar
        // 2026-06-01 is a Monday.
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let last = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 15)))
        let intervals = Stack.weekendIntervals(from: first, through: last, calendar: calendar)
        #expect(intervals.map { calendar.component(.day, from: $0.start) } == [6, 13])
        #expect(intervals.map { calendar.component(.day, from: $0.end) } == [8, 15])
    }

    @Test
    func `weekend intervals clip to the plotted range`() throws {
        let calendar = Self.utcCalendar
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let saturday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13)))
        let intervals = Stack.weekendIntervals(from: sunday, through: saturday, calendar: calendar)
        #expect(intervals.map { calendar.component(.day, from: $0.start) } == [7, 13])
        #expect(intervals.map { calendar.component(.day, from: $0.end) } == [8, 14])
        #expect(Stack.weekendIntervals(from: saturday, through: sunday, calendar: calendar).isEmpty)
    }

    @Test
    func `weekend shading stops on long ranges`() throws {
        let calendar = Self.utcCalendar
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let withinLimit = try #require(calendar.date(
            byAdding: .day, value: Stack.maxWeekendShadingDays - 1, to: first))
        let pastLimit = try #require(calendar.date(byAdding: .day, value: Stack.maxWeekendShadingDays, to: first))
        #expect(!Stack.weekendIntervals(from: first, through: withinLimit, calendar: calendar).isEmpty)
        #expect(Stack.weekendIntervals(from: first, through: pastLimit, calendar: calendar).isEmpty)
    }

    // MARK: - Fixtures

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func entry(
        _ date: String,
        cost: Double?,
        tokens: Int? = nil,
        models: [CostUsageDailyReport.ModelBreakdown]?) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: models?.map(\.modelName),
            modelBreakdowns: models)
    }
}
