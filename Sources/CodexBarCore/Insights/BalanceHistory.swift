import Foundation

/// One observed prepaid balance. Samples are stored per provider and account, never mixed.
public struct BalanceHistorySample: Codable, Equatable, Hashable, Sendable {
    public let capturedAt: Date
    public let balance: Double
    /// ISO code for monetary balances; provider units (credits, points) otherwise.
    public let currencyCode: String

    public init(capturedAt: Date, balance: Double, currencyCode: String) {
        self.capturedAt = capturedAt
        self.balance = balance
        self.currencyCode = currencyCode
    }
}

/// How much balance history is kept and how densely it is sampled.
public struct BalanceHistoryRetention: Equatable, Sendable {
    /// Width of the dedupe bucket: at most one stored sample per bucket.
    public let sampleInterval: TimeInterval
    /// Samples older than this, measured from the newest sample, are dropped.
    public let maximumAge: TimeInterval
    /// Hard cap on stored samples; the oldest are dropped first.
    public let maximumSampleCount: Int

    public init(sampleInterval: TimeInterval, maximumAge: TimeInterval, maximumSampleCount: Int) {
        self.sampleInterval = sampleInterval
        self.maximumAge = maximumAge
        self.maximumSampleCount = maximumSampleCount
    }

    /// Hourly buckets for 90 days, with headroom above 90 × 24 samples.
    public static let standard = Self(
        sampleInterval: 60 * 60,
        maximumAge: 90 * 24 * 60 * 60,
        maximumSampleCount: 2400)
}

public enum BalanceHistory {
    /// Values closer than this are treated as unchanged.
    static let unchangedTolerance: Double = 1e-9

    // MARK: - Observation

    /// The prepaid balance a provider cost snapshot reports, or nil when it reports none.
    ///
    /// Balance-only menu card styles carry the balance in `used`, matching what the menu card shows as
    /// "Balance"; every other style exposes it through `balance`.
    public static func observedBalance(
        cost: ProviderCostSnapshot,
        style: ProviderCostMenuCardStyle) -> Double?
    {
        let amount: Double? = switch style {
        case .hidden:
            nil
        case .extraUsageBalance, .zenBalance, .pointsBalance, .prepaidCredits, .payAsYouGoBalance:
            cost.used
        default:
            cost.balanceIsUnavailable == true ? nil : cost.balance
        }
        guard let amount, amount.isFinite else { return nil }
        return amount
    }

    /// The sample a provider cost snapshot contributes, timestamped when the balance was observed.
    public static func sample(
        cost: ProviderCostSnapshot,
        style: ProviderCostMenuCardStyle) -> BalanceHistorySample?
    {
        guard let balance = self.observedBalance(cost: cost, style: style) else { return nil }
        let currencyCode = cost.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currencyCode.isEmpty else { return nil }
        return BalanceHistorySample(
            capturedAt: cost.balanceUpdatedAt ?? cost.updatedAt,
            balance: balance,
            currencyCode: currencyCode)
    }

    // MARK: - Recording

    /// Returns `samples` with `sample` recorded, or nil when nothing needs to be stored.
    ///
    /// Within one sample bucket only the latest value is kept, so a changing balance stores at most one
    /// sample per bucket and an unchanged balance is stored once per bucket. Out-of-order and non-finite
    /// samples are ignored. A different unit starts a fresh history so currencies never mix.
    public static func appending(
        _ sample: BalanceHistorySample,
        to samples: [BalanceHistorySample],
        retention: BalanceHistoryRetention = .standard) -> [BalanceHistorySample]?
    {
        guard sample.balance.isFinite,
              sample.capturedAt.timeIntervalSince1970.isFinite,
              retention.sampleInterval > 0
        else { return nil }

        var updated = samples
        if let last = updated.last {
            if last.currencyCode != sample.currencyCode {
                updated = [sample]
                return self.pruned(updated, retention: retention)
            }
            guard sample.capturedAt >= last.capturedAt else { return nil }
            let unchanged = abs(sample.balance - last.balance) <= self.unchangedTolerance
            let sampleBucket = self.bucket(for: sample.capturedAt, retention: retention)
            let lastBucket = self.bucket(for: last.capturedAt, retention: retention)
            if sampleBucket == lastBucket {
                guard !unchanged else { return nil }
                updated[updated.count - 1] = sample
            } else {
                updated.append(sample)
            }
        } else {
            updated.append(sample)
        }
        return self.pruned(updated, retention: retention)
    }

    /// Drops samples past the age and count caps, measured from the newest sample.
    public static func pruned(
        _ samples: [BalanceHistorySample],
        retention: BalanceHistoryRetention = .standard) -> [BalanceHistorySample]
    {
        let sorted = samples.sorted { $0.capturedAt < $1.capturedAt }
        guard let newest = sorted.last else { return [] }
        let cutoff = newest.capturedAt.addingTimeInterval(-retention.maximumAge)
        var kept = sorted.filter { $0.capturedAt >= cutoff }
        let maximumCount = max(1, retention.maximumSampleCount)
        if kept.count > maximumCount {
            kept.removeFirst(kept.count - maximumCount)
        }
        return kept
    }

    private static func bucket(for date: Date, retention: BalanceHistoryRetention) -> Int64 {
        Int64((date.timeIntervalSince1970 / retention.sampleInterval).rounded(.down))
    }
}
