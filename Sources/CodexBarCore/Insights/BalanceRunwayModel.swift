import Foundation

/// Tuning for the balance runway estimate.
public struct BalanceRunwayConfiguration: Equatable, Sendable {
    /// Only the most recent stretch of the current segment feeds the burn rate.
    public let trailingWindow: TimeInterval
    /// Less observed decline than this is not enough signal for an estimate.
    public let minimumSpan: TimeInterval
    /// Estimates further out than this are not meaningful and are dropped.
    public let maximumHorizon: TimeInterval
    /// Increases above this amount count as a top-up and start a new segment.
    public let topUpTolerance: Double

    public init(
        trailingWindow: TimeInterval,
        minimumSpan: TimeInterval,
        maximumHorizon: TimeInterval,
        topUpTolerance: Double)
    {
        self.trailingWindow = trailingWindow
        self.minimumSpan = minimumSpan
        self.maximumHorizon = maximumHorizon
        self.topUpTolerance = topUpTolerance
    }

    public static let standard = Self(
        trailingWindow: 14 * BalanceRunwayModel.secondsPerDay,
        minimumSpan: 2 * BalanceRunwayModel.secondsPerDay,
        maximumHorizon: 730 * BalanceRunwayModel.secondsPerDay,
        topUpTolerance: 0.005)
}

/// "Lasts until …" estimate from a declining prepaid balance.
public struct BalanceRunwayEstimate: Equatable, Sendable {
    public let currentBalance: Double
    public let currencyCode: String
    /// When the latest balance was observed; days left are counted from here.
    public let observedAt: Date
    /// First sample of the stretch the burn rate is measured over.
    public let basisStart: Date
    /// Average decline per day over the basis stretch; always positive.
    public let burnPerDay: Double
    public let daysLeft: Double
    public let depletionDate: Date
}

public enum BalanceRunwayModel {
    public static let secondsPerDay: TimeInterval = 24 * 60 * 60

    /// Samples since the most recent top-up: an increase above `topUpTolerance` starts a new segment.
    public static func currentSegment(
        _ samples: [BalanceHistorySample],
        topUpTolerance: Double = BalanceRunwayConfiguration.standard.topUpTolerance) -> [BalanceHistorySample]
    {
        let sorted = self.sortedSamplesInLatestUnit(samples)
        guard !sorted.isEmpty else { return [] }
        var segmentStart = sorted.startIndex
        for index in sorted.indices.dropFirst() {
            let increase = sorted[index].balance - sorted[index - 1].balance
            if increase > topUpTolerance {
                segmentStart = index
            }
        }
        return Array(sorted[segmentStart...])
    }

    /// Burn rate over the trailing window of the current segment, projected to zero.
    ///
    /// Returns nil without enough signal: fewer than two samples, less than `minimumSpan` of data since the
    /// last top-up, a flat or rising balance, an empty balance, or a depletion beyond `maximumHorizon`.
    public static func estimate(
        samples: [BalanceHistorySample],
        configuration: BalanceRunwayConfiguration = .standard) -> BalanceRunwayEstimate?
    {
        let segment = self.currentSegment(samples, topUpTolerance: configuration.topUpTolerance)
        guard let latest = segment.last else { return nil }
        let windowStart = latest.capturedAt.addingTimeInterval(-configuration.trailingWindow)
        let basis = segment.filter { $0.capturedAt >= windowStart }
        guard basis.count >= 2, let first = basis.first else { return nil }

        let span = latest.capturedAt.timeIntervalSince(first.capturedAt)
        guard span.isFinite, span >= configuration.minimumSpan, span > 0 else { return nil }

        let decline = first.balance - latest.balance
        let burnPerDay = decline / (span / self.secondsPerDay)
        guard burnPerDay.isFinite, burnPerDay > 0, latest.balance > 0 else { return nil }

        let daysLeft = latest.balance / burnPerDay
        let secondsLeft = daysLeft * self.secondsPerDay
        guard daysLeft.isFinite, secondsLeft <= configuration.maximumHorizon else { return nil }

        return BalanceRunwayEstimate(
            currentBalance: latest.balance,
            currencyCode: latest.currencyCode,
            observedAt: latest.capturedAt,
            basisStart: first.capturedAt,
            burnPerDay: burnPerDay,
            daysLeft: daysLeft,
            depletionDate: latest.capturedAt.addingTimeInterval(secondsLeft))
    }

    /// Sorted samples sharing the newest sample's unit, so a currency switch never feeds the math.
    static func sortedSamplesInLatestUnit(_ samples: [BalanceHistorySample]) -> [BalanceHistorySample] {
        let sorted = samples
            .filter { $0.balance.isFinite }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard let unit = sorted.last?.currencyCode else { return [] }
        return sorted.filter { $0.currencyCode == unit }
    }
}

/// Points for the menu runway chart: the observed balance line and a projection to zero.
public struct BalanceRunwayChartModel: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let date: Date
        public let balance: Double

        public init(date: Date, balance: Double) {
            self.date = date
            self.balance = balance
        }
    }

    /// Observed balances inside the display window, oldest first. Top-ups show as steps up.
    public let history: [Point]
    /// From the latest balance to zero, or to the display horizon when zero lies further out.
    public let projection: [Point]
    /// True when the projection reaches zero inside the chart.
    public let projectionReachesZero: Bool
    public let domainStart: Date
    public let domainEnd: Date
    /// Largest balance drawn, for the y domain.
    public let maximumBalance: Double
    public let estimate: BalanceRunwayEstimate

    public static let defaultDisplayWindow: TimeInterval = 30 * BalanceRunwayModel.secondsPerDay
    public static let defaultProjectionHorizon: TimeInterval = 60 * BalanceRunwayModel.secondsPerDay

    public init?(
        samples: [BalanceHistorySample],
        estimate: BalanceRunwayEstimate,
        displayWindow: TimeInterval = Self.defaultDisplayWindow,
        projectionHorizon: TimeInterval = Self.defaultProjectionHorizon)
    {
        let windowStart = estimate.observedAt.addingTimeInterval(-displayWindow)
        let history = BalanceRunwayModel.sortedSamplesInLatestUnit(samples)
            .filter { $0.currencyCode == estimate.currencyCode }
            .filter { $0.capturedAt >= windowStart && $0.capturedAt <= estimate.observedAt }
            .map { Point(date: $0.capturedAt, balance: max(0, $0.balance)) }
        guard history.count >= 2, let first = history.first else { return nil }

        let horizonEnd = estimate.observedAt.addingTimeInterval(max(0, projectionHorizon))
        let reachesZero = estimate.depletionDate <= horizonEnd
        let projectionEnd = reachesZero ? estimate.depletionDate : horizonEnd
        let elapsedDays = projectionEnd.timeIntervalSince(estimate.observedAt) / BalanceRunwayModel.secondsPerDay
        let projectedBalance = reachesZero ? 0 : max(0, estimate.currentBalance - estimate.burnPerDay * elapsedDays)

        self.history = history
        self.projection = [
            Point(date: estimate.observedAt, balance: max(0, estimate.currentBalance)),
            Point(date: projectionEnd, balance: projectedBalance),
        ]
        self.projectionReachesZero = reachesZero
        self.domainStart = first.date
        self.domainEnd = max(projectionEnd, estimate.observedAt)
        self.maximumBalance = history.map(\.balance).max() ?? estimate.currentBalance
        self.estimate = estimate
    }
}
