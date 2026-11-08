import Foundation
import SharinganCore
import Testing

/// Compact account rows classify each window through the user's warning thresholds instead of the old
/// fixed 50% / 10% cut-offs, which now only survive as the standard bands.
struct AccountMenuLayoutPlannerSeverityTests {
    private static let now = Date(timeIntervalSince1970: 1_782_000_000)

    private func account(
        slot: Int,
        isActive: Bool = false,
        sessionUsed: Double? = nil,
        weeklyUsed: Double? = nil,
        tertiaryUsed: Double? = nil) -> ProviderAccountUsageSnapshot
    {
        func window(_ used: Double?, minutes: Int) -> RateWindow? {
            used.map {
                RateWindow(
                    usedPercent: $0,
                    windowMinutes: minutes,
                    resetsAt: Self.now.addingTimeInterval(3600),
                    resetDescription: nil)
            }
        }
        return ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: "claude-swap", opaqueID: String(slot)),
            provider: .claude,
            displayLabel: "account\(slot)@example.com",
            isActive: isActive,
            canActivate: true,
            snapshot: UsageSnapshot(
                primary: window(sessionUsed, minutes: 300),
                secondary: window(weeklyUsed, minutes: 7 * 24 * 60),
                tertiary: window(tertiaryUsed, minutes: 7 * 24 * 60),
                updatedAt: Self.now,
                identity: nil),
            error: nil,
            sourceLabel: "claude-swap")
    }

    private func fixture() -> [ProviderAccountUsageSnapshot] {
        [
            self.account(slot: 1, isActive: true, sessionUsed: 5),
            self.account(slot: 2, sessionUsed: 75),
            self.account(slot: 3, sessionUsed: 85),
            self.account(slot: 4, sessionUsed: 40),
            self.account(slot: 5, sessionUsed: 5),
        ]
    }

    private func severities(
        _ accounts: [ProviderAccountUsageSnapshot],
        bands: QuotaSeverityBandSet) -> [String: AccountMenuLayoutPlanner.Severity]
    {
        let plan = AccountMenuLayoutPlanner.plan(accounts: accounts, healthyTailExpanded: true, severityBands: bands)
        var result: [String: AccountMenuLayoutPlanner.Severity] = [:]
        for row in plan.rows {
            if case let .compact(compact) = row {
                result[compact.accountID.opaqueID] = compact.severity
            }
        }
        return result
    }

    @Test
    func `standard bands keep the historical classification`() {
        let severities = self.severities(self.fixture(), bands: .standard)

        #expect(severities["2"] == .warning)
        #expect(severities["3"] == .warning)
        #expect(severities["4"] == .healthy)
        #expect(severities["5"] == .healthy)
        #expect(AccountMenuLayoutPlanner.severity(forHeadroom: 10) == .critical)
        #expect(AccountMenuLayoutPlanner.severity(forHeadroom: 50) == .warning)
        #expect(AccountMenuLayoutPlanner.severity(forHeadroom: 50.5) == .healthy)
    }

    @Test
    func `custom session thresholds reclassify compact rows`() {
        let tight = QuotaSeverityBandSet(session: .from(thresholds: [30, 20]))
        let tightSeverities = self.severities(self.fixture(), bands: tight)
        #expect(tightSeverities["2"] == .warning)
        #expect(tightSeverities["3"] == .critical)
        #expect(tightSeverities["4"] == .healthy)

        let early = QuotaSeverityBandSet(session: .from(thresholds: [70, 50]))
        let earlySeverities = self.severities(self.fixture(), bands: early)
        #expect(earlySeverities["2"] == .critical)
        #expect(earlySeverities["3"] == .critical)
        #expect(earlySeverities["4"] == .warning)
        #expect(earlySeverities["5"] == .healthy)
    }

    @Test
    func `constrained details and the best candidate follow the user's bands`() throws {
        let early = QuotaSeverityBandSet(session: .from(thresholds: [70, 50]))
        let plan = AccountMenuLayoutPlanner.plan(
            accounts: self.fixture(),
            healthyTailExpanded: true,
            severityBands: early)
        let rows = plan.rows.compactMap { row -> AccountMenuLayoutPlanner.CompactRow? in
            if case let .compact(compact) = row { return compact }
            return nil
        }
        let warning = try #require(rows.first { $0.accountID.opaqueID == "4" })
        #expect(warning.windowDetails.map(\.metricID) == ["primary"])
        #expect(warning.isBestCandidate == false)
        #expect(rows.first { $0.accountID.opaqueID == "5" }?.isBestCandidate == true)

        let everythingWarns = QuotaSeverityBandSet(session: .from(thresholds: [99, 98]))
        let strictRows = AccountMenuLayoutPlanner.plan(
            accounts: self.fixture(),
            healthyTailExpanded: true,
            severityBands: everythingWarns).rows
        let hasBest = strictRows.contains { row in
            if case let .compact(compact) = row { return compact.isBestCandidate }
            return false
        }
        #expect(hasBest == false)
    }

    @Test
    func `third windows use their lane override or fall back to weekly`() {
        let accounts = [
            self.account(slot: 1, isActive: true, sessionUsed: 5),
            self.account(slot: 2, sessionUsed: 0, weeklyUsed: 0, tertiaryUsed: 70),
            self.account(slot: 3, sessionUsed: 0),
            self.account(slot: 4, sessionUsed: 0),
        ]

        #expect(self.severities(accounts, bands: .standard)["2"] == .warning)

        let weeklyOnly = QuotaSeverityBandSet(weekly: .from(thresholds: [40, 35]))
        #expect(self.severities(accounts, bands: weeklyOnly)["2"] == .critical)

        let laneOverride = QuotaSeverityBandSet(
            weekly: .from(thresholds: [40, 35]),
            lanes: [QuotaWarningLaneID.tertiary: .from(thresholds: [20, 10])])
        #expect(self.severities(accounts, bands: laneOverride)["2"] == .healthy)
    }

    @Test
    func `row severity maps to shared levels and back`() {
        #expect(AccountMenuLayoutPlanner.Severity(level: .normal) == .healthy)
        #expect(AccountMenuLayoutPlanner.Severity(level: .warning) == .warning)
        #expect(AccountMenuLayoutPlanner.Severity(level: .critical) == .critical)
        #expect(AccountMenuLayoutPlanner.Severity(level: .exhausted) == .critical)
        #expect(AccountMenuLayoutPlanner.Severity.healthy.level == .normal)
        #expect(AccountMenuLayoutPlanner.Severity.critical.level == .critical)
    }
}
