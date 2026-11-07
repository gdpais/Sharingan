import CodexBarCore
import Testing

struct TomoeIconFillsTests {
    @Test
    func `percents map to clamped fill fractions`() {
        #expect(TomoeIconFills.fraction(percent: 46) == 0.46)
        #expect(TomoeIconFills.fraction(percent: 0) == 0)
        #expect(TomoeIconFills.fraction(percent: 100) == 1)
        #expect(TomoeIconFills.fraction(percent: 140) == 1)
        #expect(TomoeIconFills.fraction(percent: -12) == 0)
        #expect(TomoeIconFills.fraction(percent: nil) == nil)
        #expect(TomoeIconFills.fraction(percent: .nan) == nil)
        #expect(TomoeIconFills.fraction(percent: .infinity) == nil)
    }

    @Test
    func `fractions are clamped and missing windows stay missing`() {
        let fills = TomoeIconFills(session: 1.5, weekly: -0.2, monthly: nil)
        #expect(fills.session == 1)
        #expect(fills.weekly == 0)
        #expect(fills.monthly == nil)
        #expect(TomoeIconFills(session: .nan, weekly: nil, monthly: nil) == .empty)

        let fromPercents = TomoeIconFills(sessionPercent: 25, weeklyPercent: nil, monthlyPercent: 250)
        #expect(fromPercents.fraction(for: .session) == 0.25)
        #expect(fromPercents.fraction(for: .weekly) == nil)
        #expect(fromPercents.fraction(for: .monthly) == 1)
    }

    @Test
    func `window lengths pick the session weekly or monthly tomoe`() {
        #expect(TomoeIconFills.slot(windowMinutes: 5 * 60) == .session)
        #expect(TomoeIconFills.slot(windowMinutes: 24 * 60) == .session)
        #expect(TomoeIconFills.slot(windowMinutes: 7 * 24 * 60) == .weekly)
        #expect(TomoeIconFills.slot(windowMinutes: 30 * 24 * 60) == .monthly)
        #expect(TomoeIconFills.slot(windowMinutes: nil) == nil)
        #expect(TomoeIconFills.slot(windowMinutes: 0) == nil)
    }

    @Test
    func `lanes without a window length keep their position`() {
        let fills = TomoeIconFills.assigning([
            .init(percent: 80, windowMinutes: nil),
            .init(percent: 40, windowMinutes: nil),
            .init(percent: 10, windowMinutes: nil),
        ])
        #expect(fills == TomoeIconFills(session: 0.8, weekly: 0.4, monthly: 0.1))
    }

    @Test
    func `missing lanes are drawn as missing tomoe`() {
        let fills = TomoeIconFills.assigning([.init(percent: 60, windowMinutes: 300), nil, nil])
        #expect(fills == TomoeIconFills(session: 0.6, weekly: nil, monthly: nil))
        #expect(TomoeIconFills.assigning([]) == .empty)
        #expect(TomoeIconFills.assigning([nil, .init(percent: .nan, windowMinutes: nil)]) == .empty)
    }

    @Test
    func `a monthly lane moves to the monthly tomoe`() {
        // Plans with only a monthly window must not read as a full session.
        let fills = TomoeIconFills.assigning([.init(percent: 30, windowMinutes: 30 * 24 * 60), nil, nil])
        #expect(fills == TomoeIconFills(session: nil, weekly: nil, monthly: 0.3))
    }

    @Test
    func `a second weekly window never fills the monthly tomoe`() {
        let fills = TomoeIconFills.assigning([
            .init(percent: 90, windowMinutes: 300),
            .init(percent: 50, windowMinutes: 7 * 24 * 60),
            .init(percent: 20, windowMinutes: 7 * 24 * 60),
        ])
        #expect(fills == TomoeIconFills(session: 0.9, weekly: 0.5, monthly: nil))
    }

    @Test
    func `only the first three lanes are considered`() {
        let fills = TomoeIconFills.assigning([nil, nil, nil, .init(percent: 70, windowMinutes: nil)])
        #expect(fills == .empty)
    }

    @Test
    func `signature is stable and distinguishes missing from empty`() {
        #expect(TomoeIconFills(session: 0.4567, weekly: 0, monthly: nil).signature == "457,0,nil")
        #expect(TomoeIconFills(session: nil, weekly: nil, monthly: nil).signature == "nil,nil,nil")
        #expect(TomoeIconFills(session: 1, weekly: 1, monthly: 1).signature == "1000,1000,1000")
    }
}
