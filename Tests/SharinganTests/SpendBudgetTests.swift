import Foundation
import Testing
@testable import SharinganCore

struct SpendBudgetTests {
    // MARK: - Month to date

    @Test
    func `month to date sums only this month's days through today`() throws {
        let status = try #require(SpendBudgetStatus.make(
            daily: [
                Self.entry("2026-10-31", cost: 100),
                Self.entry("2026-11-01", cost: 10),
                Self.entry("2026-11-18", cost: 2.5),
                Self.entry("2026-11-19", cost: 50),
            ],
            budget: 50,
            now: Self.date("2026-11-18T12:00:00Z"),
            calendar: Self.utc,
            coverage: (start: Self.date("2026-10-20T00:00:00Z"), isPartial: false)))
        #expect(status.month.key == "2026-11")
        #expect(status.month.dayCount == 30)
        #expect(status.monthToDateCost == 12.5)
        #expect(status.fraction == 0.25)
        #expect(status.dailyShare == 50.0 / 30.0)
        #expect(status.isComplete)
    }

    @Test
    func `late history a partial scan or unpriced usage make the figure a floor`() throws {
        let now = Self.date("2026-11-18T12:00:00Z")
        let daily = [Self.entry("2026-11-10", cost: 5)]
        let monthStart = Self.date("2026-10-01T00:00:00Z")
        let make = { (daily: [CostUsageDailyReport.Entry], start: Date?, isPartial: Bool) in
            SpendBudgetStatus.make(
                daily: daily,
                budget: 50,
                now: now,
                calendar: Self.utc,
                coverage: (start: start, isPartial: isPartial))
        }
        let late = try #require(make(daily, Self.date("2026-11-05T00:00:00Z"), false))
        #expect(!late.isComplete)
        let partial = try #require(make(daily, monthStart, true))
        #expect(!partial.isComplete)
        let unknown = try #require(make(daily, nil, false))
        #expect(!unknown.isComplete)
        let covered = try #require(make(daily, monthStart, false))
        #expect(covered.isComplete)

        let unpriced = try #require(make(daily + [Self.entry("2026-11-11", cost: nil, tokens: 500)], monthStart, false))
        #expect(!unpriced.isComplete)
        #expect(unpriced.monthToDateCost == 5)

        // A priced day with requests the catalog could not price is a floor too.
        let partlyPriced = CostUsageDailyReport.Entry(
            date: "2026-11-12",
            inputTokens: 900,
            outputTokens: 0,
            totalTokens: 900,
            costUSD: 3,
            modelsUsed: nil,
            modelBreakdowns: nil,
            unpricedRequestCount: 2)
        let partlyPricedStatus = try #require(make(daily + [partlyPriced], monthStart, false))
        #expect(!partlyPricedStatus.isComplete)
        #expect(partlyPricedStatus.monthToDateCost == 8)
        let vendorMetered = CostUsageDailyReport.Entry(
            date: "2026-11-12",
            inputTokens: 900,
            outputTokens: 0,
            totalTokens: 900,
            costUSD: 3,
            modelsUsed: ["fixture-alpha", "fixture-beta"],
            modelBreakdowns: [
                CostUsageDailyReport.ModelBreakdown(modelName: "fixture-alpha", costUSD: nil, totalTokens: 400),
                CostUsageDailyReport.ModelBreakdown(modelName: "fixture-beta", costUSD: nil, totalTokens: 500),
            ])
        // Vendor-metered days (OpenAI API) carry the day's full cost with unpriced model rows: still exact.
        #expect(try #require(make(daily + [vendorMetered], monthStart, false)).isComplete)

        #expect(SpendBudgetStatus.make(daily: daily, budget: 0, now: now, calendar: Self.utc) == nil)
        let noRate = SpendBudgetStatus.make(daily: daily, budget: 50, now: now, calendar: Self.utc, costMultiplier: 0)
        #expect(noRate == nil)
    }

    @Test
    func `snapshots cover their history window ending on their update day`() throws {
        let now = Self.date("2026-11-18T12:00:00Z")
        let month = Self.snapshot(historyDays: 30, daily: [Self.entry("2026-11-02", cost: 4)], updatedAt: now)
        let status = try #require(SpendBudgetStatus.make(
            snapshot: month, budget: 20, now: now, calendar: Self.utc, costMultiplier: 0.5))
        #expect(status.monthToDateCost == 2)
        #expect(status.isComplete)

        let week = Self.snapshot(historyDays: 7, daily: [Self.entry("2026-11-15", cost: 4)], updatedAt: now)
        let weekStatus = try #require(SpendBudgetStatus.make(snapshot: week, budget: 20, now: now, calendar: Self.utc))
        #expect(weekStatus.monthToDateCost == 4)
        #expect(!weekStatus.isComplete)
    }

    @Test
    func `the budget month follows the cost time zone`() throws {
        let instant = Self.date("2026-11-30T23:30:00Z")
        #expect(SpendBudgetMonth.containing(instant, calendar: Self.utc)?.key == "2026-11")
        let berlin = try #require(SpendBudgetMonth.containing(instant, calendar: Self.calendar("Europe/Berlin")))
        #expect(berlin.key == "2026-12")
        #expect(berlin.dayCount == 31)
        #expect(berlin.todayKey == "2026-12-01")
        let losAngeles = SpendBudgetMonth.containing(
            Self.date("2026-12-01T05:00:00Z"),
            calendar: Self.calendar("America/Los_Angeles"))
        #expect(losAngeles?.key == "2026-11")
        #expect(SpendBudgetMonth.containing(Self.date("2028-02-10T12:00:00Z"), calendar: Self.utc)?.dayCount == 29)
    }

    // MARK: - Alerts

    @Test
    func `each threshold is announced once per month`() {
        let first = SpendBudgetAlerts.evaluate(status: Self.status(cost: 41), currencyCode: "USD", previous: nil)
        #expect(first.newlyReachedPercents == [80])
        #expect(first.announcedPercent == 80)

        let again = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 45),
            currencyCode: "USD",
            previous: first.state)
        #expect(again.newlyReachedPercents.isEmpty)
        #expect(again.state == first.state)

        let over = SpendBudgetAlerts.evaluate(status: Self.status(cost: 51), currencyCode: "USD", previous: again.state)
        #expect(over.announcedPercent == 100)
        #expect(over.state.announcedPercents == [80, 100])

        // A rescan that lowers the estimate does not re-arm thresholds already announced.
        let lowered = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 30),
            currencyCode: "USD",
            previous: over.state)
        #expect(lowered.newlyReachedPercents.isEmpty)
        #expect(lowered.state == over.state)

        let december = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 45, now: "2026-12-02T08:00:00Z"),
            currencyCode: "USD",
            previous: over.state)
        #expect(december.state.monthKey == "2026-12")
        #expect(december.newlyReachedPercents == [80])
        #expect(december.state.announcedPercents == [80])
    }

    @Test
    func `crossing both thresholds in one refresh announces the higher one`() {
        let jump = SpendBudgetAlerts.evaluate(status: Self.status(cost: 60), currencyCode: "USD", previous: nil)
        #expect(jump.newlyReachedPercents == [80, 100])
        #expect(jump.announcedPercent == 100)
        let below = SpendBudgetAlerts.evaluate(status: Self.status(cost: 39.99), currencyCode: "USD", previous: nil)
        #expect(below.announcedPercent == nil)
        #expect(below.state.announcedPercents.isEmpty)
    }

    @Test
    func `a new budget amount or currency starts the month over`() {
        let reached = SpendBudgetAlerts.evaluate(status: Self.status(cost: 45), currencyCode: "USD", previous: nil)
        let raised = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 45, budget: 100),
            currencyCode: "USD",
            previous: reached.state)
        #expect(raised.newlyReachedPercents.isEmpty)
        #expect(raised.state.announcedPercents.isEmpty)
        let raisedReached = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 85, budget: 100),
            currencyCode: "USD",
            previous: raised.state)
        #expect(raisedReached.newlyReachedPercents == [80])
        let euros = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 45),
            currencyCode: "EUR",
            previous: reached.state)
        #expect(euros.newlyReachedPercents == [80])
    }

    @Test
    func `the dedupe month follows the cost time zone across a boundary`() throws {
        let instant = "2026-11-30T23:30:00Z"
        let utc = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 45, now: instant),
            currencyCode: "USD",
            previous: nil)
        #expect(utc.state.monthKey == "2026-11")
        // The same instant is already December in Berlin, so the November announcement does not carry over.
        let berlin = SpendBudgetAlerts.evaluate(
            status: Self.status(cost: 45, now: instant, calendar: Self.calendar("Europe/Berlin")),
            currencyCode: "USD",
            previous: utc.state)
        #expect(berlin.state.monthKey == "2026-12")
        #expect(berlin.newlyReachedPercents == [80])

        let data = try JSONEncoder().encode(berlin.state)
        #expect(try JSONDecoder().decode(SpendBudgetAlertState.self, from: data) == berlin.state)
    }

    // MARK: - Hook event

    @Test
    func `budget events name every amount as estimated`() throws {
        let month = try #require(SpendBudgetMonth.containing(Self.date("2026-11-18T09:30:00Z"), calendar: Self.utc))
        let event = HookEvent.budgetReached(
            provider: "claude",
            status: SpendBudgetStatus(
                month: month,
                budget: 50,
                monthToDateCost: 41,
                isComplete: false),
            threshold: 0.8,
            currencyCode: "USD",
            timestamp: Self.date("2026-11-18T09:30:00Z"))

        let payload = try event.jsonPayload()
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(Set(object.keys) == [
            "budget", "budgetMonth", "budgetThreshold", "currency", "estimatedBudgetFraction", "estimatedCost",
            "estimatedCostIsPartial", "event", "provider", "timestamp", "window",
        ])
        #expect(object["event"] as? String == "budget_reached")
        #expect(object["estimatedCost"] as? Double == 41)
        #expect(object["budget"] as? Double == 50)
        #expect(object["estimatedBudgetFraction"] as? Double == 0.82)
        #expect(object["budgetThreshold"] as? Double == 0.8)
        #expect(object["budgetMonth"] as? String == "2026-11")
        #expect(object["estimatedCostIsPartial"] as? Bool == true)
        #expect(object["window"] as? String == "month")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(HookEvent.self, from: payload) == event)

        let env = event.environmentVariables()
        #expect(env["SHARINGAN_EVENT"] == "budget_reached")
        #expect(env["SHARINGAN_ESTIMATED_COST"] == "41")
        #expect(env["SHARINGAN_BUDGET"] == "50")
        #expect(env["SHARINGAN_ESTIMATED_BUDGET_FRACTION"] == "0.82")
        #expect(env["SHARINGAN_BUDGET_THRESHOLD"] == "0.8")
        #expect(env["SHARINGAN_CURRENCY"] == "USD")
        #expect(env["SHARINGAN_BUDGET_MONTH"] == "2026-11")
        #expect(env["SHARINGAN_ESTIMATED_COST_IS_PARTIAL"] == "true")
        #expect(env["SHARINGAN_ACCOUNT"] == nil)
    }

    @Test
    func `quota events keep their payload without budget fields`() throws {
        let event = HookEvent(
            event: .quotaReached,
            provider: "claude",
            window: "session",
            usagePercent: 0.42,
            timestamp: Self.date("2026-11-18T09:30:00Z"))
        let object = try #require(JSONSerialization.jsonObject(with: event.jsonPayload()) as? [String: Any])
        #expect(Set(object.keys) == ["event", "provider", "timestamp", "usagePercent", "window"])
        #expect(!event.environmentVariables().keys.contains { $0.contains("BUDGET") || $0.contains("ESTIMATED") })
    }

    @Test
    func `budget rules match budget events and stay out of the shared config editor`() {
        #expect(!HookEventType.sharedConfigCases.contains(.budgetReached))
        #expect(HookEventType.sharedConfigCases.count == HookEventType.allCases.count - 1)
        #expect(!HookEventType.budgetReached.isRateLimited)

        let event = HookEvent.budgetReached(
            provider: "claude",
            status: Self.status(cost: 41),
            threshold: 0.8,
            currencyCode: "USD")
        #expect(HookRule(event: .budgetReached, provider: "claude", executable: "/usr/bin/true").matches(event))
        #expect(HookRule(event: .budgetReached, executable: "/usr/bin/true").matches(event))
        #expect(!HookRule(event: .budgetReached, provider: "codex", executable: "/usr/bin/true").matches(event))
        #expect(!HookRule(event: .quotaLow, executable: "/usr/bin/true").matches(event))
    }
}

// MARK: - Fixtures

extension SpendBudgetTests {
    private static let utc = Self.calendar("UTC")

    private static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private static func entry(_ day: String, cost: Double?, tokens: Int = 1000) -> CostUsageDailyReport.Entry {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: tokens,
            outputTokens: 0,
            totalTokens: tokens,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }

    private static func snapshot(
        historyDays: Int,
        daily: [CostUsageDailyReport.Entry],
        updatedAt: Date) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            historyDays: historyDays,
            daily: daily,
            updatedAt: updatedAt)
    }

    private static func status(
        cost: Double,
        budget: Double = 50,
        now: String = "2026-11-18T12:00:00Z",
        calendar: Calendar = Self.utc) -> SpendBudgetStatus
    {
        SpendBudgetStatus(
            month: SpendBudgetMonth.containing(self.date(now), calendar: calendar)!,
            budget: budget,
            monthToDateCost: cost,
            isComplete: true)
    }
}
