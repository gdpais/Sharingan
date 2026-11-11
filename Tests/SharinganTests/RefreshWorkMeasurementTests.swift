import Foundation
import SharinganCore
import Testing
@testable import Sharingan

/// Measures each refresh-work gate against a control arm that bypasses it, and prints one `MEASURE` line per
/// arm so a CI log carries the numbers. The control arms reproduce the pre-gate triggers: every token
/// publication counted as new usage, every widget publication saved, every provider's history reconciled.
@MainActor
@Suite(.serialized)
struct RefreshWorkMeasurementTests {
    // MARK: - All-time dashboard scans

    private static func allTimeScans(refreshes: Int, gated: Bool) async throws -> Int {
        let fixture = try SpendDashboardFreshnessFixture()
        defer { fixture.cleanup() }
        fixture.installSyntheticLoader()
        await fixture.store.refreshSpendDashboardTokenUsageNow(for: .claude, force: true)
        for _ in 0..<refreshes {
            await fixture.store.refreshTokenUsageNow(for: .claude, force: true)
            if !gated {
                fixture.store.tokenSnapshotContentRevisions[UsageProvider.claude.instanceID, default: 0] &+= 1
            }
            _ = await fixture.request()
        }
        return fixture.requests.count(where: { $0 == SpendDashboardSource.scanDays })
    }

    @Test
    func `all-time scans across unchanged cost refreshes with and without the content gate`() async throws {
        let refreshes = 10
        let control = try await Self.allTimeScans(refreshes: refreshes, gated: false)
        let gated = try await Self.allTimeScans(refreshes: refreshes, gated: true)
        print("MEASURE all-time-scans refreshes=\(refreshes) control=\(control) gated=\(gated)")
        #expect(gated < control)
    }

    // MARK: - Widget snapshot writes

    private struct WidgetWrites {
        var publications = 0
        var writes = 0
    }

    /// `cycles` refresh cycles of `publicationsPerCycle` publications each. With `advancingFetchTime`, each
    /// cycle carries a newer provider fetch time and the same usage, as a successful refresh does.
    private static func widgetWrites(
        cycles: Int,
        publicationsPerCycle: Int,
        advancingFetchTime: Bool,
        gated: Bool) async -> WidgetWrites
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshWorkMeasurementTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("widget.json")
        let environment = ["HOME": root.path, "CODEX_HOME": root.appendingPathComponent("codex").path]
        let settings = testSettingsStore(
            suiteName: "RefreshWorkMeasurementTests-\(UUID().uuidString)",
            userDefaults: InMemoryUserDefaults(),
            config: testConfigWithAllProvidersDisabled())
        settings._test_codexReconciliationEnvironment = environment
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        enableTestProviders([.codex], settings: settings)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: root.path, fileExists: { _ in false }),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: root
                .appendingPathComponent("history.json")),
            planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
            startupBehavior: .testing,
            environmentBase: environment,
            widgetSnapshotURL: url,
            widgetTimelineReloader: {})
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var result = WidgetWrites()
        var lastFileNumber: Int?
        for cycle in 0..<cycles {
            let fetchedAt = advancingFetchTime ? start.addingTimeInterval(Double(cycle) * 300) : start
            store._setSnapshotForTesting(
                UsageSnapshot(
                    primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                    secondary: nil,
                    updatedAt: fetchedAt),
                provider: .codex)
            for _ in 0..<publicationsPerCycle {
                if !gated {
                    store.lastSavedWidgetSnapshotFingerprint = nil
                }
                store.persistWidgetSnapshot(reason: "measurement")
                await store.widgetSnapshotPersistTask?.value
                result.publications += 1
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.intValue
                if fileNumber != nil, fileNumber != lastFileNumber {
                    result.writes += 1
                    lastFileNumber = fileNumber
                }
            }
        }
        return result
    }

    @Test
    func `widget writes across identical publications with and without the content gate`() async {
        let control = await Self.widgetWrites(
            cycles: 1,
            publicationsPerCycle: 6,
            advancingFetchTime: false,
            gated: false)
        let gated = await Self.widgetWrites(cycles: 1, publicationsPerCycle: 6, advancingFetchTime: false, gated: true)
        print(
            "MEASURE widget-writes-identical publications=\(gated.publications) " +
                "control=\(control.writes) gated=\(gated.writes)")
        #expect(gated.writes < control.writes)
    }

    @Test
    func `widget writes across refresh cycles that fetch the same usage again`() async {
        let control = await Self.widgetWrites(
            cycles: 12,
            publicationsPerCycle: 4,
            advancingFetchTime: true,
            gated: false)
        let gated = await Self.widgetWrites(cycles: 12, publicationsPerCycle: 4, advancingFetchTime: true, gated: true)
        print(
            "MEASURE widget-writes-cycles cycles=12 publications=\(gated.publications) " +
                "control=\(control.writes) gated=\(gated.writes)")
        #expect(gated.writes <= control.writes)
    }

    // MARK: - Plan-utilization history saves

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    private static func yearOfHourlySamples(extra: Int = 0) -> PlanUtilizationHistoryBuckets {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let entries = (0..<(8760 + extra)).map { hour in
            PlanUtilizationHistoryEntry(
                capturedAt: start.addingTimeInterval(Double(hour) * 3600),
                usedPercent: Double(hour % 100),
                resetsAt: start.addingTimeInterval(Double(hour) * 3600 + 18000))
        }
        var buckets = PlanUtilizationHistoryBuckets()
        buckets.unscoped = [PlanUtilizationSeriesHistory(name: .session, windowMinutes: 300, entries: entries)]
        return buckets
    }

    @Test
    func `plan history save cost when one of five providers gains a sample`() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshWorkMeasurementTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlanUtilizationHistoryStore(directoryURL: directory)
        let instanceIDs = UsageProvider.allCases.prefix(5).map(\.instanceID)
        let changed = instanceIDs[0]
        var snapshot: [ProviderInstanceID: PlanUtilizationHistoryBuckets] = [:]
        for instanceID in instanceIDs {
            snapshot[instanceID] = Self.yearOfHourlySamples()
        }
        #expect(store.save(snapshot))

        let clock = ContinuousClock()
        var fullSaves: [Double] = []
        var restrictedSaves: [Double] = []
        for round in 1...5 {
            snapshot[changed] = Self.yearOfHourlySamples(extra: round * 2 - 1)
            let full = snapshot
            fullSaves.append(Self.milliseconds(clock.measure { _ = store.save(full) }))
            snapshot[changed] = Self.yearOfHourlySamples(extra: round * 2)
            let restricted = snapshot
            restrictedSaves.append(Self.milliseconds(clock.measure {
                _ = store.save(restricted, changedInstanceIDs: [changed])
            }))
        }
        #expect(store.load() == snapshot)
        let control = Self.median(fullSaves)
        let gated = Self.median(restrictedSaves)
        print(
            "MEASURE plan-history-save providersVisited control=\(UsageProvider.allCases.count) gated=1 " +
                "medianMs control=\(String(format: "%.1f", control)) gated=\(String(format: "%.1f", gated))")
        #expect(gated < control)
    }

    // MARK: - Refresh cycles while the display is inactive

    @Test
    func `refresh cycles over eight hours with the display inactive`() {
        let locked: TimeInterval = 8 * 60 * 60
        for frequency in RefreshFrequency.allCases {
            guard let seconds = frequency.seconds else { continue }
            let active = UsageStore.effectiveAutomaticRefreshInterval(
                seconds,
                lowPowerModeEnabled: false,
                displayInactive: false) ?? seconds
            let inactive = UsageStore.effectiveAutomaticRefreshInterval(
                seconds,
                lowPowerModeEnabled: false,
                displayInactive: true) ?? seconds
            print(
                "MEASURE locked-refresh-cycles frequency=\(frequency.rawValue) " +
                    "control=\(Int(locked / active)) gated=\(Int(locked / inactive))")
            #expect(inactive >= active)
        }
        #expect(UsageStore.effectiveAutomaticRefreshInterval(
            300,
            lowPowerModeEnabled: false,
            displayInactive: true) == 1800)
    }
}
