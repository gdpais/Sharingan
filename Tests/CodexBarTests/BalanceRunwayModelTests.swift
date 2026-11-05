import Foundation
import Testing
@testable import CodexBarCore

struct BalanceRunwayModelTests {
    private static let day: TimeInterval = 86400
    private static let start = Date(timeIntervalSince1970: 1_699_999_200)

    private static func sample(day: Double, _ balance: Double, currencyCode: String = "USD") -> BalanceHistorySample {
        BalanceHistorySample(
            capturedAt: self.start.addingTimeInterval(day * self.day),
            balance: balance,
            currencyCode: currencyCode)
    }

    private static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    // MARK: - Burn rate

    @Test
    func `steady decline gives burn rate days left and depletion date`() throws {
        let samples = (0...5).map { Self.sample(day: Double($0), 10 - Double($0)) }

        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))

        #expect(Self.isClose(estimate.burnPerDay, 1))
        #expect(Self.isClose(estimate.daysLeft, 5))
        #expect(estimate.currentBalance == 5)
        #expect(estimate.currencyCode == "USD")
        #expect(estimate.observedAt == Self.start.addingTimeInterval(5 * Self.day))
        #expect(estimate.basisStart == Self.start)
        #expect(abs(estimate.depletionDate.timeIntervalSince(Self.start.addingTimeInterval(10 * Self.day))) < 1e-3)
    }

    @Test
    func `burn rate averages the decline across uneven samples`() throws {
        let samples = [
            Self.sample(day: 0, 30),
            Self.sample(day: 0.5, 30),
            Self.sample(day: 1, 24),
            Self.sample(day: 3, 21),
            Self.sample(day: 4, 18),
        ]

        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))

        #expect(Self.isClose(estimate.burnPerDay, 3))
        #expect(Self.isClose(estimate.daysLeft, 6))
    }

    @Test
    func `only the trailing window feeds the burn rate`() throws {
        let configuration = BalanceRunwayConfiguration(
            trailingWindow: 7 * Self.day,
            minimumSpan: 2 * Self.day,
            maximumHorizon: 730 * Self.day,
            topUpTolerance: 0.005)
        // A steep 5/day burn for ten days, then 1/day for the last ten.
        let steep = (0...10).map { Self.sample(day: Double($0), 100 - 5 * Double($0)) }
        let gentle = (11...20).map { Self.sample(day: Double($0), 50 - Double($0 - 10)) }

        let estimate = try #require(BalanceRunwayModel.estimate(
            samples: steep + gentle,
            configuration: configuration))

        #expect(Self.isClose(estimate.burnPerDay, 1))
        #expect(estimate.basisStart == Self.start.addingTimeInterval(13 * Self.day))
    }

    @Test
    func `samples are sorted before measuring`() throws {
        let samples = (0...4).map { Self.sample(day: Double($0), 20 - 2 * Double($0)) }.reversed()

        let estimate = try #require(BalanceRunwayModel.estimate(samples: Array(samples)))

        #expect(Self.isClose(estimate.burnPerDay, 2))
        #expect(estimate.currentBalance == 12)
    }

    // MARK: - Top-ups

    @Test
    func `a top up starts a new segment`() throws {
        let samples = [
            Self.sample(day: 0, 20),
            Self.sample(day: 1, 18),
            Self.sample(day: 2, 16),
            Self.sample(day: 3, 14),
            Self.sample(day: 4, 30),
            Self.sample(day: 5, 29),
            Self.sample(day: 6, 28),
            Self.sample(day: 7, 27),
        ]

        #expect(BalanceRunwayModel.currentSegment(samples).map(\.balance) == [30, 29, 28, 27])
        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))
        #expect(Self.isClose(estimate.burnPerDay, 1))
        #expect(Self.isClose(estimate.daysLeft, 27))
        #expect(estimate.basisStart == Self.start.addingTimeInterval(4 * Self.day))
    }

    @Test
    func `a recent top up leaves too little data for an estimate`() {
        let samples = [
            Self.sample(day: 0, 20),
            Self.sample(day: 1, 18),
            Self.sample(day: 2, 16),
            Self.sample(day: 3, 30),
            Self.sample(day: 4.5, 29),
        ]

        #expect(BalanceRunwayModel.estimate(samples: samples) == nil)
    }

    @Test
    func `increases within the tolerance do not reset the segment`() {
        let samples = [
            Self.sample(day: 0, 10),
            Self.sample(day: 1, 9),
            Self.sample(day: 2, 9.004),
            Self.sample(day: 3, 8),
        ]

        #expect(BalanceRunwayModel.currentSegment(samples).count == 4)
    }

    // MARK: - Not enough signal

    @Test
    func `fewer than two days of data gives no estimate`() {
        #expect(BalanceRunwayModel.estimate(samples: []) == nil)
        #expect(BalanceRunwayModel.estimate(samples: [Self.sample(day: 0, 10)]) == nil)
        #expect(BalanceRunwayModel.estimate(samples: [
            Self.sample(day: 0, 10),
            Self.sample(day: 1, 8),
            Self.sample(day: 1.9, 6),
        ]) == nil)
    }

    @Test
    func `flat or rising balances give no estimate`() {
        let flat = (0...4).map { Self.sample(day: Double($0), 10) }
        let rising = [Self.sample(day: 0, 10), Self.sample(day: 2, 10.004), Self.sample(day: 4, 10.004)]

        #expect(BalanceRunwayModel.estimate(samples: flat) == nil)
        #expect(BalanceRunwayModel.estimate(samples: rising) == nil)
    }

    @Test
    func `an empty balance or a far horizon gives no estimate`() {
        let empty = (0...3).map { Self.sample(day: Double($0), 3 - Double($0)) }
        let slow = (0...3).map { Self.sample(day: Double($0), 100 - 0.01 * Double($0)) }

        #expect(BalanceRunwayModel.estimate(samples: empty) == nil)
        #expect(BalanceRunwayModel.estimate(samples: slow) == nil)
    }

    @Test
    func `samples in an older unit are ignored`() throws {
        let dollars = (0...3).map { Self.sample(day: Double($0), 50 - 10 * Double($0)) }
        let euros = (4...7).map { Self.sample(day: Double($0), 40 - Double($0 - 4), currencyCode: "EUR") }

        let estimate = try #require(BalanceRunwayModel.estimate(samples: dollars + euros))

        #expect(estimate.currencyCode == "EUR")
        #expect(Self.isClose(estimate.burnPerDay, 1))
        #expect(BalanceRunwayModel.estimate(samples: dollars + Array(euros.prefix(2))) == nil)
    }

    // MARK: - Chart

    @Test
    func `chart projects to zero inside the horizon`() throws {
        let samples = (0...5).map { Self.sample(day: Double($0), 10 - Double($0)) }
        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))

        let chart = try #require(BalanceRunwayChartModel(samples: samples, estimate: estimate))

        #expect(chart.history.count == 6)
        #expect(chart.projectionReachesZero)
        #expect(chart.projection.first == BalanceRunwayChartModel.Point(date: estimate.observedAt, balance: 5))
        #expect(chart.projection.last?.balance == 0)
        #expect(chart.projection.last?.date == estimate.depletionDate)
        #expect(chart.domainStart == Self.start)
        #expect(chart.domainEnd == estimate.depletionDate)
        #expect(chart.maximumBalance == 10)
    }

    @Test
    func `chart clamps a distant projection at the horizon`() throws {
        let samples = (0...5).map { Self.sample(day: Double($0), 10 - Double($0)) }
        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))

        let chart = try #require(BalanceRunwayChartModel(
            samples: samples,
            estimate: estimate,
            projectionHorizon: 2 * Self.day))

        #expect(!chart.projectionReachesZero)
        #expect(chart.projection.last?.date == estimate.observedAt.addingTimeInterval(2 * Self.day))
        #expect(Self.isClose(chart.projection.last?.balance ?? -1, 3))
    }

    @Test
    func `chart keeps only the display window and shows top ups as steps`() throws {
        let old = Self.sample(day: 0, 80)
        let recent = [
            Self.sample(day: 40, 20),
            Self.sample(day: 41, 18),
            Self.sample(day: 42, 40),
            Self.sample(day: 43, 38),
            Self.sample(day: 45, 34),
        ]
        let samples = [old] + recent
        let estimate = try #require(BalanceRunwayModel.estimate(samples: samples))

        let chart = try #require(BalanceRunwayChartModel(samples: samples, estimate: estimate))

        #expect(chart.history.map(\.balance) == [20, 18, 40, 38, 34])
        #expect(chart.maximumBalance == 40)
        #expect(Self.isClose(estimate.burnPerDay, 2))
    }
}
