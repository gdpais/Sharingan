import CodexBarCore
import Foundation
import Testing

struct QuotaSeverityLevelTests {
    @Test
    func `standard bands keep the historical warning and critical cut-offs`() {
        let bands = QuotaSeverityBands.standard

        #expect(bands.level(remainingPercent: 100) == .normal)
        #expect(bands.level(remainingPercent: 50.1) == .normal)
        #expect(bands.level(remainingPercent: 50) == .warning)
        #expect(bands.level(remainingPercent: 10.1) == .warning)
        #expect(bands.level(remainingPercent: 10) == .critical)
        #expect(bands.level(remainingPercent: 0.1) == .critical)
        #expect(bands.level(remainingPercent: 0) == .exhausted)
        #expect(bands.level(remainingPercent: -4) == .exhausted)
        #expect(bands.level(remainingPercent: .nan) == .normal)
    }

    @Test
    func `used percent maps through remaining percent`() {
        let bands = QuotaSeverityBands.standard

        #expect(bands.level(usedPercent: 49.9) == .normal)
        #expect(bands.level(usedPercent: 50) == .warning)
        #expect(bands.level(usedPercent: 90) == .critical)
        #expect(bands.level(usedPercent: 100) == .exhausted)
        #expect(bands.level(usedPercent: 130) == .exhausted)
        #expect(bands.level(usedPercent: .infinity) == .normal)
    }

    @Test
    func `untouched default thresholds keep the standard bands`() {
        #expect(QuotaSeverityBands.from(thresholds: QuotaWarningThresholds.defaults) == .standard)
        #expect(QuotaSeverityBands.from(thresholds: [20, 50]) == .standard)
        #expect(QuotaSeverityBands.from(thresholds: []) == .standard)
    }

    @Test
    func `custom thresholds set warning from the first and critical from the second`() {
        let bands = QuotaSeverityBands.from(thresholds: [5, 75, 30, 15])

        #expect(bands.warningRemainingPercent == 75)
        #expect(bands.criticalRemainingPercent == 30)
        #expect(bands.level(remainingPercent: 76) == .normal)
        #expect(bands.level(remainingPercent: 75) == .warning)
        #expect(bands.level(remainingPercent: 30) == .critical)
        #expect(bands.level(remainingPercent: 3) == .critical)
        #expect(QuotaSeverityBands.level(usedPercent: 40, thresholds: [75, 30]) == .warning)
    }

    @Test
    func `single and depleted only threshold lists narrow the bands`() {
        let single = QuotaSeverityBands.from(thresholds: [30])
        #expect(single.warningRemainingPercent == 30)
        #expect(single.criticalRemainingPercent == nil)
        #expect(single.level(remainingPercent: 2) == .warning)

        let depletedOnly = QuotaSeverityBands.from(thresholds: [0])
        #expect(depletedOnly.warningRemainingPercent == nil)
        #expect(depletedOnly.criticalRemainingPercent == nil)
        #expect(depletedOnly.level(remainingPercent: 1) == .normal)
        #expect(depletedOnly.level(remainingPercent: 0) == .exhausted)
    }

    @Test
    func `levels order from normal to exhausted`() {
        #expect(QuotaSeverityLevel.allCases.sorted() == [.normal, .warning, .critical, .exhausted])
        #expect([QuotaSeverityLevel.warning, .exhausted, .normal].max() == .exhausted)
    }

    @Test
    func `band set resolves lanes with a weekly fallback`() {
        let session = QuotaSeverityBands(warningRemainingPercent: 60, criticalRemainingPercent: 25)
        let weekly = QuotaSeverityBands(warningRemainingPercent: 40, criticalRemainingPercent: 15)
        let tertiary = QuotaSeverityBands(warningRemainingPercent: 30, criticalRemainingPercent: 5)
        let set = QuotaSeverityBandSet(session: session, weekly: weekly, lanes: ["tertiary": tertiary])

        #expect(set.bands(forLaneID: "primary") == session)
        #expect(set.bands(forLaneID: "session") == session)
        #expect(set.bands(forLaneID: "secondary") == weekly)
        #expect(set.bands(forLaneID: "weekly") == weekly)
        #expect(set.bands(forLaneID: "tertiary") == tertiary)
        #expect(set.bands(forLaneID: "fictional-extra-window") == weekly)
        #expect(!set.isStandard)
        #expect(QuotaSeverityBandSet.standard.isStandard)
    }

    @Test
    func `band set round trips and tolerates missing members`() throws {
        let set = QuotaSeverityBandSet(
            session: QuotaSeverityBands(warningRemainingPercent: 60, criticalRemainingPercent: nil),
            lanes: ["tertiary": QuotaSeverityBands(warningRemainingPercent: 30, criticalRemainingPercent: 5)])
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(QuotaSeverityBandSet.self, from: data) == set)

        let partial = try JSONDecoder().decode(
            QuotaSeverityBandSet.self,
            from: Data(#"{"weekly":{"warningRemainingPercent":40}}"#.utf8))
        #expect(partial.session == .standard)
        #expect(partial.weekly == QuotaSeverityBands(warningRemainingPercent: 40, criticalRemainingPercent: nil))
        #expect(partial.lanes.isEmpty)
    }
}
