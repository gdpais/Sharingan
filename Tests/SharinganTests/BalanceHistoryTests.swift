import Foundation
import Testing
@testable import SharinganCore

struct BalanceHistoryTests {
    /// Aligned to the start of an hour bucket so minute offsets stay inside it.
    private static let hourStart = Date(timeIntervalSince1970: 1_699_999_200)

    private static func sample(
        minutes: Double,
        _ balance: Double,
        currencyCode: String = "USD") -> BalanceHistorySample
    {
        BalanceHistorySample(
            capturedAt: self.hourStart.addingTimeInterval(minutes * 60),
            balance: balance,
            currencyCode: currencyCode)
    }

    // MARK: - Dedupe

    @Test
    func `first sample is stored`() {
        let first = Self.sample(minutes: 0, 10)
        #expect(BalanceHistory.appending(first, to: []) == [first])
    }

    @Test
    func `unchanged balance within the same hour is not stored again`() {
        let history = [Self.sample(minutes: 0, 10)]
        #expect(BalanceHistory.appending(Self.sample(minutes: 30, 10), to: history) == nil)
        #expect(BalanceHistory.appending(Self.sample(minutes: 59, 10.000_000_000_1), to: history) == nil)
    }

    @Test
    func `changed balance within the same hour replaces the latest sample`() {
        let history = [Self.sample(minutes: -30, 12), Self.sample(minutes: 5, 10)]
        let latest = Self.sample(minutes: 50, 9.5)

        #expect(BalanceHistory.appending(latest, to: history) == [Self.sample(minutes: -30, 12), latest])
    }

    @Test
    func `unchanged balance in a new hour is stored as an hourly sample`() {
        let history = [Self.sample(minutes: 0, 10)]
        let nextHour = Self.sample(minutes: 61, 10)

        #expect(BalanceHistory.appending(nextHour, to: history) == history + [nextHour])
    }

    @Test
    func `out of order and non finite samples are ignored`() {
        let history = [Self.sample(minutes: 120, 10)]

        #expect(BalanceHistory.appending(Self.sample(minutes: 0, 8), to: history) == nil)
        #expect(BalanceHistory.appending(Self.sample(minutes: 180, .nan), to: history) == nil)
        #expect(BalanceHistory.appending(Self.sample(minutes: 180, .infinity), to: history) == nil)
    }

    @Test
    func `a different unit starts a fresh history`() {
        let history = [Self.sample(minutes: 0, 10), Self.sample(minutes: 60, 9)]
        let euros = Self.sample(minutes: 120, 8, currencyCode: "EUR")

        #expect(BalanceHistory.appending(euros, to: history) == [euros])
    }

    // MARK: - Caps

    @Test
    func `history drops samples older than the maximum age`() {
        let retention = BalanceHistoryRetention(sampleInterval: 3600, maximumAge: 2 * 86400, maximumSampleCount: 100)
        let history = [
            Self.sample(minutes: 0, 10),
            Self.sample(minutes: 24 * 60, 9),
        ]
        let latest = Self.sample(minutes: 2.5 * 24 * 60, 8)

        let updated = BalanceHistory.appending(latest, to: history, retention: retention)
        #expect(updated == [Self.sample(minutes: 24 * 60, 9), latest])
    }

    @Test
    func `history keeps at most the maximum sample count`() {
        let retention = BalanceHistoryRetention(sampleInterval: 3600, maximumAge: 365 * 86400, maximumSampleCount: 3)
        var history: [BalanceHistorySample] = []
        for hour in 0..<6 {
            history = BalanceHistory.appending(
                Self.sample(minutes: Double(hour) * 60, 100 - Double(hour)),
                to: history,
                retention: retention) ?? history
        }

        #expect(history.map(\.balance) == [97, 96, 95])
    }

    @Test
    func `standard retention keeps ninety days of hourly samples`() {
        let retention = BalanceHistoryRetention.standard
        #expect(retention.sampleInterval == 3600)
        #expect(retention.maximumAge == 90 * 86400)
        #expect(retention.maximumSampleCount >= 90 * 24)
    }

    // MARK: - Observation

    @Test
    func `balance only card styles read the balance from used`() {
        let cost = ProviderCostSnapshot(
            used: 12.5,
            limit: 0,
            currencyCode: "USD",
            balance: 99,
            updatedAt: Self.hourStart)
        let styles: [ProviderCostMenuCardStyle] = [
            .extraUsageBalance,
            .zenBalance,
            .pointsBalance,
            .prepaidCredits,
            .payAsYouGoBalance,
        ]
        for style in styles {
            #expect(BalanceHistory.observedBalance(cost: cost, style: style) == 12.5)
        }
    }

    @Test
    func `other card styles read the reported balance`() {
        let observedAt = Self.hourStart.addingTimeInterval(-600)
        let cost = ProviderCostSnapshot(
            used: 3,
            limit: 0,
            currencyCode: "USD",
            balance: 41,
            balanceUpdatedAt: observedAt,
            updatedAt: Self.hourStart)

        #expect(BalanceHistory.observedBalance(cost: cost, style: .payAsYouGoSpend) == 41)
        #expect(BalanceHistory.observedBalance(cost: cost, style: .generic) == 41)
        #expect(BalanceHistory.sample(cost: cost, style: .payAsYouGoSpend) == BalanceHistorySample(
            capturedAt: observedAt,
            balance: 41,
            currencyCode: "USD"))
    }

    @Test
    func `hidden styles missing and unavailable balances produce no sample`() {
        let spendOnly = ProviderCostSnapshot(used: 3, limit: 10, currencyCode: "USD", updatedAt: Self.hourStart)
        #expect(BalanceHistory.observedBalance(cost: spendOnly, style: .payAsYouGoSpend) == nil)
        #expect(BalanceHistory.observedBalance(cost: spendOnly, style: .hidden) == nil)

        var unavailable = ProviderCostSnapshot(
            used: 3,
            limit: 0,
            currencyCode: "USD",
            balance: 41,
            updatedAt: Self.hourStart)
        unavailable.balanceIsUnavailable = true
        #expect(BalanceHistory.sample(cost: unavailable, style: .generic) == nil)
    }
}
