import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexLogQuotaBackfillTests {
    /// 2026-10-01T10:00:00Z, the start of a clock hour.
    private static let hourStart = Date(timeIntervalSince1970: 1_790_848_800)
    /// Four hours after `hourStart`.
    private static let sessionReset = Date(timeIntervalSince1970: 1_790_863_200)
    /// Five days after `hourStart`.
    private static let weeklyReset = Date(timeIntervalSince1970: 1_791_280_800)

    private static func at(minutes: Double) -> Date {
        self.hourStart.addingTimeInterval(minutes * 60)
    }

    private static func sample(
        minutes: Double,
        session: Double?,
        weekly: Double?,
        creator: String? = nil) -> CodexRateLimitLogSample
    {
        CodexRateLimitLogSample(
            observedAt: self.at(minutes: minutes),
            primary: session.map {
                CodexRateLimitLogWindow(usedPercent: $0, windowMinutes: 300, resetsAt: self.sessionReset)
            },
            secondary: weekly.map {
                CodexRateLimitLogWindow(usedPercent: $0, windowMinutes: 10080, resetsAt: self.weeklyReset)
            },
            creatorAccountID: creator)
    }

    /// Two clock hours of readings plus a monthly window that is out of scope for the backfill.
    private static var twoHoursOfSamples: [CodexRateLimitLogSample] {
        [
            self.sample(minutes: 5, session: 10, weekly: 30),
            CodexRateLimitLogSample(
                observedAt: self.at(minutes: 10),
                primary: CodexRateLimitLogWindow(usedPercent: 50, windowMinutes: 43200, resetsAt: nil),
                secondary: nil),
            self.sample(minutes: 30, session: 25, weekly: 31),
            self.sample(minutes: 50, session: 20, weekly: 31),
            self.sample(minutes: 70, session: 40, weekly: 35),
        ]
    }

    private static func backfill(
        _ samples: [CodexRateLimitLogSample],
        into histories: [PlanUtilizationSeriesHistory],
        notBefore horizon: Date = .distantPast) -> [PlanUtilizationSeriesHistory]?
    {
        PlanUtilizationHistoryStore.codexHistoriesBackfillingLogSamples(
            samples,
            into: histories,
            notBefore: horizon)
    }

    @Test
    func `folds log samples into hourly peaks for session and weekly windows`() throws {
        let updated = try #require(Self.backfill(Self.twoHoursOfSamples, into: []))

        #expect(updated.map { "\($0.name.rawValue):\($0.windowMinutes)" } == ["session:300", "weekly:10080"])
        let session = try #require(findSeries(updated, name: .session, windowMinutes: 300))
        #expect(session.entries.map(\.usedPercent) == [25, 40])
        #expect(session.entries.map(\.capturedAt) == [Self.at(minutes: 30), Self.at(minutes: 70)])
        #expect(session.entries.allSatisfy { $0.resetsAt == Self.sessionReset })
        let weekly = try #require(findSeries(updated, name: .weekly, windowMinutes: 10080))
        // Equal peaks keep the most recent reading, as live hourly folding does.
        #expect(weekly.entries.map(\.usedPercent) == [31, 35])
        #expect(weekly.entries.map(\.capturedAt) == [Self.at(minutes: 50), Self.at(minutes: 70)])
    }

    @Test
    func `never overwrites hours that already have recorded entries`() throws {
        let liveSession = planEntry(at: Self.at(minutes: 20), usedPercent: 15, resetsAt: Self.sessionReset)
        let liveWeekly = planEntry(at: Self.at(minutes: 65), usedPercent: 33, resetsAt: Self.weeklyReset)
        let existing = [
            planSeries(name: .session, windowMinutes: 300, entries: [liveSession]),
            planSeries(name: .weekly, windowMinutes: 10080, entries: [liveWeekly]),
        ]

        let updated = try #require(Self.backfill(Self.twoHoursOfSamples, into: existing))

        let session = try #require(findSeries(updated, name: .session, windowMinutes: 300))
        #expect(session.entries.first == liveSession)
        #expect(session.entries.map(\.usedPercent) == [15, 40])
        let weekly = try #require(findSeries(updated, name: .weekly, windowMinutes: 10080))
        #expect(weekly.entries.last == liveWeekly)
        #expect(weekly.entries.map(\.usedPercent) == [31, 33])
    }

    @Test
    func `near canonical recorded series still count as recorded hours`() throws {
        let legacySession = planEntry(at: Self.at(minutes: 15), usedPercent: 5)
        let existing = [planSeries(name: .session, windowMinutes: 299, entries: [legacySession])]

        let updated = try #require(Self.backfill(Self.twoHoursOfSamples, into: existing))

        #expect(findSeries(updated, name: .session, windowMinutes: 299)?.entries == [legacySession])
        #expect(findSeries(updated, name: .session, windowMinutes: 300)?.entries.map(\.usedPercent) == [40])
    }

    @Test
    func `repeated backfill over the same logs changes nothing`() throws {
        let first = try #require(Self.backfill(Self.twoHoursOfSamples, into: []))

        #expect(Self.backfill(Self.twoHoursOfSamples, into: first) == nil)
        #expect(Self.backfill([], into: first) == nil)
    }

    @Test
    func `ignores samples before the horizon and stays within retention`() throws {
        let recent = try #require(Self.backfill(
            Self.twoHoursOfSamples,
            into: [],
            notBefore: Self.at(minutes: 60)))
        #expect(findSeries(recent, name: .session, windowMinutes: 300)?.entries.map(\.usedPercent) == [40])

        let retainedCount = UsageStore.planUtilizationMaxSamples - 1
        let oldest = Self.hourStart.addingTimeInterval(-TimeInterval(retainedCount + 24) * 60 * 60)
        let recorded = (0..<retainedCount).map { hour in
            planEntry(at: oldest.addingTimeInterval(TimeInterval(hour) * 60 * 60), usedPercent: 1)
        }
        let full = try #require(Self.backfill(
            Self.twoHoursOfSamples,
            into: [planSeries(name: .session, windowMinutes: 300, entries: recorded)]))

        let session = try #require(findSeries(full, name: .session, windowMinutes: 300))
        #expect(session.entries.count == UsageStore.planUtilizationMaxSamples)
        #expect(session.entries.first == recorded.first)
        // Only the newest backfilled hour fits; recorded entries are never evicted for it.
        #expect(session.entries.last?.usedPercent == 40)
    }

    @Test
    func `backfill requires exactly one configured codex account`() {
        #expect(UsageStore.codexLogQuotaBackfillAllowsAccounts(
            visibleAccountCount: 1,
            tokenAccountCount: 0,
            hasAdjacentMultiAccountVeto: false))
        #expect(!UsageStore.codexLogQuotaBackfillAllowsAccounts(
            visibleAccountCount: 0,
            tokenAccountCount: 0,
            hasAdjacentMultiAccountVeto: false))
        #expect(!UsageStore.codexLogQuotaBackfillAllowsAccounts(
            visibleAccountCount: 2,
            tokenAccountCount: 0,
            hasAdjacentMultiAccountVeto: false))
        #expect(!UsageStore.codexLogQuotaBackfillAllowsAccounts(
            visibleAccountCount: 1,
            tokenAccountCount: 1,
            hasAdjacentMultiAccountVeto: false))
        #expect(!UsageStore.codexLogQuotaBackfillAllowsAccounts(
            visibleAccountCount: 1,
            tokenAccountCount: 0,
            hasAdjacentMultiAccountVeto: true))
    }

    @Test
    func `attribution keeps only rollouts created by the configured workspace`() {
        let own = Self.sample(minutes: 5, session: 10, weekly: 30, creator: "acct-a")
        let foreign = Self.sample(minutes: 30, session: 90, weekly: 80, creator: "acct-b")
        let unknown = Self.sample(minutes: 50, session: 20, weekly: 31)

        let mixed = UsageStore.codexLogQuotaBackfillAttribution(
            [own, foreign, unknown],
            accountWorkspaceID: " ACCT-A ",
            knownCreatorAccountIDHashes: [])
        // Once another account appears, rollouts without a creator can no longer be attributed.
        #expect(mixed.samples == [own])
        #expect(mixed.creatorAccountIDHashes == [
            UsageStore.codexLogQuotaBackfillAccountIDHash("acct-a"),
            UsageStore.codexLogQuotaBackfillAccountIDHash("acct-b"),
        ])

        let ownOnly = UsageStore.codexLogQuotaBackfillAttribution(
            [own, unknown],
            accountWorkspaceID: "acct-a",
            knownCreatorAccountIDHashes: [])
        #expect(ownOnly.samples == [own, unknown])

        let previouslyForeign = UsageStore.codexLogQuotaBackfillAttribution(
            [own, unknown],
            accountWorkspaceID: "acct-a",
            knownCreatorAccountIDHashes: [UsageStore.codexLogQuotaBackfillAccountIDHash("acct-b")])
        #expect(previouslyForeign.samples == [own])
    }

    @Test
    func `attribution without a workspace id requires a single creator`() {
        let first = Self.sample(minutes: 5, session: 10, weekly: 30, creator: "acct-a")
        let second = Self.sample(minutes: 30, session: 90, weekly: 80, creator: "acct-b")
        let unknown = Self.sample(minutes: 50, session: 20, weekly: 31)

        let single = UsageStore.codexLogQuotaBackfillAttribution(
            [first, unknown],
            accountWorkspaceID: nil,
            knownCreatorAccountIDHashes: [])
        #expect(single.samples == [first, unknown])

        let anonymous = UsageStore.codexLogQuotaBackfillAttribution(
            [unknown],
            accountWorkspaceID: "  ",
            knownCreatorAccountIDHashes: [])
        #expect(anonymous.samples == [unknown])
        #expect(anonymous.creatorAccountIDHashes.isEmpty)

        let twoCreators = UsageStore.codexLogQuotaBackfillAttribution(
            [first, second, unknown],
            accountWorkspaceID: nil,
            knownCreatorAccountIDHashes: [])
        #expect(twoCreators.samples.isEmpty)

        // A creator remembered from an earlier pass keeps vetoing later incremental passes.
        let remembered = UsageStore.codexLogQuotaBackfillAttribution(
            [first, unknown],
            accountWorkspaceID: nil,
            knownCreatorAccountIDHashes: [UsageStore.codexLogQuotaBackfillAccountIDHash("acct-b")])
        #expect(remembered.samples.isEmpty)
    }
}
