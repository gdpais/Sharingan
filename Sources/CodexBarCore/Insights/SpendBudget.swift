import Foundation

// MARK: - Month

/// One calendar month in the cost bucket calendar, which decides both the month-to-date window and the
/// month a budget alert belongs to.
public struct SpendBudgetMonth: Sendable, Equatable {
    /// `yyyy-MM`, the prefix every day key of the month shares.
    public let key: String
    public let start: Date
    public let dayCount: Int
    /// `yyyy-MM-dd` of the day containing `now`.
    public let todayKey: String

    public init(key: String, start: Date, dayCount: Int, todayKey: String) {
        self.key = key
        self.start = start
        self.dayCount = dayCount
        self.todayKey = todayKey
    }

    public static func containing(_ now: Date, calendar: Calendar) -> SpendBudgetMonth? {
        let calendar = CostUsageLocalDay.gregorianCalendar(matching: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now)?.count,
              days > 0
        else { return nil }
        let todayKey = CostUsageLocalDay.key(from: now, calendar: calendar)
        return SpendBudgetMonth(
            key: String(todayKey.prefix(7)),
            start: interval.start,
            dayCount: days,
            todayKey: todayKey)
    }
}

// MARK: - Status

/// Estimated month-to-date spend against a monthly budget, both in the budget's currency.
public struct SpendBudgetStatus: Sendable, Equatable {
    public let month: SpendBudgetMonth
    public let budget: Double
    public let monthToDateCost: Double
    /// `false` when history does not reach back to the first of the month, a scan stopped short, or a day
    /// has unpriced usage. The month-to-date figure is then a floor.
    public let isComplete: Bool

    public init(month: SpendBudgetMonth, budget: Double, monthToDateCost: Double, isComplete: Bool) {
        self.month = month
        self.budget = budget
        self.monthToDateCost = monthToDateCost
        self.isComplete = isComplete
    }

    /// Month-to-date spend as a fraction of the budget; above 1 once the budget is exceeded.
    public var fraction: Double {
        self.monthToDateCost / self.budget
    }

    /// The budget spread evenly over the month's days: the reference a daily bar can be read against.
    public var dailyShare: Double {
        self.budget / Double(self.month.dayCount)
    }

    /// - Parameters:
    ///   - daily: Day rows whose keys are calendar days in `calendar`.
    ///   - budget: Monthly budget in the budget's currency.
    ///   - costMultiplier: Converts the rows' cost currency into the budget's currency.
    ///   - coverageStart: First day the rows are known to cover; `nil` when unknown.
    ///   - isPartial: The rows are known to be a floor (a scan stopped short).
    public static func make(
        daily: [CostUsageDailyReport.Entry],
        budget: Double,
        now: Date,
        calendar: Calendar,
        costMultiplier: Double = 1,
        coverage: (start: Date?, isPartial: Bool) = (nil, false)) -> SpendBudgetStatus?
    {
        guard let budget = ProviderSpendPlan.validAmount(budget),
              costMultiplier.isFinite, costMultiplier > 0,
              let month = SpendBudgetMonth.containing(now, calendar: calendar)
        else { return nil }
        let prefix = month.key + "-"
        var total = 0.0
        var hasUnpricedDay = false
        for entry in daily {
            guard let day = CostUsageTokenSnapshot.localDayKey(for: entry.date, calendar: calendar),
                  day.hasPrefix(prefix), day <= month.todayKey
            else { continue }
            if let cost = entry.costUSD, cost.isFinite, cost >= 0 {
                total += cost * costMultiplier
                // A priced day can still hold requests the catalog could not price; its cost is then a floor.
                if Self.hasUnpricedRequests(entry) {
                    hasUnpricedDay = true
                }
            } else if (entry.totalTokens ?? 0) > 0 || entry.incompleteRequestCount > 0 {
                hasUnpricedDay = true
            }
        }
        guard total.isFinite else { return nil }
        let reachesMonthStart = coverage.start.map { $0 <= month.start } ?? false
        return SpendBudgetStatus(
            month: month,
            budget: budget,
            monthToDateCost: total,
            isComplete: reachesMonthStart && !coverage.isPartial && !hasUnpricedDay)
    }

    /// Unpriced or incomplete requests: the signals the Spend dashboard reads as a lower-bound cost. Model rows
    /// without a cost do not count on their own, since vendor-metered providers (OpenAI API) report the day's
    /// complete cost with unpriced model rows. Unmetered requests cost nothing by design, so they do not count.
    static func hasUnpricedRequests(_ entry: CostUsageDailyReport.Entry) -> Bool {
        entry.coverageCounts.unpriced > 0 || entry.incompleteRequestCount > 0
    }

    /// Month-to-date status from a cost snapshot. The snapshot covers `historyDays` days ending on its
    /// update day, or all history for an all-time window.
    public static func make(
        snapshot: CostUsageTokenSnapshot,
        budget: Double,
        now: Date,
        calendar: Calendar,
        costMultiplier: Double = 1) -> SpendBudgetStatus?
    {
        let coverageStart: Date? = if !snapshot.historyCoverageIsEstablished {
            nil
        } else if snapshot.reportingPeriod == .allTime {
            Date.distantPast
        } else {
            CostReportingPeriod.rolling(days: max(1, snapshot.historyDays))
                .bounds(now: snapshot.updatedAt, calendar: calendar)
                .lowerBound
        }
        return self.make(
            daily: snapshot.daily,
            budget: budget,
            now: now,
            calendar: calendar,
            costMultiplier: costMultiplier,
            coverage: (coverageStart, snapshot.historyScanIsPartial))
    }
}

// MARK: - Alerts

/// What was already announced for one provider's budget this month. Persisted so each threshold is
/// announced once per calendar month, across relaunches.
public struct SpendBudgetAlertState: Codable, Sendable, Equatable {
    public var monthKey: String
    public var budget: Double
    public var currencyCode: String
    /// Threshold percents already announced, ascending.
    public var announcedPercents: [Int]

    public init(monthKey: String, budget: Double, currencyCode: String, announcedPercents: [Int] = []) {
        self.monthKey = monthKey
        self.budget = budget
        self.currencyCode = currencyCode
        self.announcedPercents = announcedPercents
    }
}

public enum SpendBudgetAlerts {
    /// Percent of the monthly budget at which spend is announced.
    public static let thresholdPercents = [80, 100]

    public struct Evaluation: Sendable, Equatable {
        public let state: SpendBudgetAlertState
        /// Thresholds reached for the first time this month for this budget, ascending.
        public let newlyReachedPercents: [Int]

        public init(state: SpendBudgetAlertState, newlyReachedPercents: [Int]) {
            self.state = state
            self.newlyReachedPercents = newlyReachedPercents
        }

        /// One announcement covers every threshold a single refresh reached: the highest one.
        public var announcedPercent: Int? {
            self.newlyReachedPercents.max()
        }
    }

    /// Compares month-to-date spend with each threshold. A new month, or a changed budget amount or
    /// currency, starts from a clean slate; otherwise thresholds already announced stay quiet even if a
    /// later rescan lowers the estimate.
    public static func evaluate(
        status: SpendBudgetStatus,
        currencyCode: String,
        previous: SpendBudgetAlertState?) -> Evaluation
    {
        var state = SpendBudgetAlertState(
            monthKey: status.month.key,
            budget: status.budget,
            currencyCode: currencyCode)
        if let previous,
           previous.monthKey == state.monthKey,
           previous.budget == state.budget,
           previous.currencyCode == state.currencyCode
        {
            state = previous
        }
        let reached = self.thresholdPercents.filter { percent in
            status.monthToDateCost >= status.budget * Double(percent) / 100
        }
        let newlyReached = reached.filter { !state.announcedPercents.contains($0) }
        state.announcedPercents = Array(Set(state.announcedPercents).union(reached)).sorted()
        return Evaluation(state: state, newlyReachedPercents: newlyReached)
    }
}
