import Testing
@testable import CodexBar

struct ChartNiceScaleTests {
    @Test
    func `ticks extend to a nice ceiling with three to five values`() {
        #expect(ChartNiceScale.ticks(maximum: 1515) == [0, 500, 1000, 1500, 2000])
        #expect(ChartNiceScale.ticks(maximum: 1000) == [0, 500, 1000])
        #expect(ChartNiceScale.ticks(maximum: 7.3) == [0, 2, 4, 6, 8])
        #expect(ChartNiceScale.ticks(maximum: 12) == [0, 5, 10, 15])
        for maximum in [0.07, 0.5, 3, 12, 99, 1515, 49_000, 151_000_000] {
            let ticks = ChartNiceScale.ticks(maximum: maximum)
            #expect((3...5).contains(ticks.count))
            #expect((ticks.last ?? 0) >= maximum)
        }
    }

    @Test
    func `small values keep decimal steps without floating point noise`() {
        #expect(ChartNiceScale.ticks(maximum: 0.5) == [0, 0.2, 0.4, 0.6])
        #expect(ChartNiceScale.ticks(maximum: 0.07) == [0, 0.02, 0.04, 0.06, 0.08])
        #expect(ChartNiceScale.ticks(maximum: 0.5, minimumStep: 1) == [0, 1])
    }

    @Test
    func `flat negative and non-finite maxima produce no ticks`() {
        #expect(ChartNiceScale.ticks(maximum: 0).isEmpty)
        #expect(ChartNiceScale.ticks(maximum: -4).isEmpty)
        #expect(ChartNiceScale.ticks(maximum: .nan).isEmpty)
        #expect(ChartNiceScale.ticks(maximum: .infinity).isEmpty)
    }

    @Test
    func `nice value rounds up to one two or five times a power of ten`() {
        #expect(ChartNiceScale.niceValue(atLeast: 151) == 200)
        #expect(ChartNiceScale.niceValue(atLeast: 200) == 200)
        #expect(ChartNiceScale.niceValue(atLeast: 200, strictlyAbove: true) == 500)
        #expect(ChartNiceScale.niceValue(atLeast: 6) == 10)
        #expect(ChartNiceScale.niceValue(atLeast: 0) == nil)
    }
}
