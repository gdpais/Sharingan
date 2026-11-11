import Foundation
import Testing
@testable import Sharingan
@testable import SharinganCore

/// Counts the work a run of unchanged refreshes causes. Before these gates existed every unchanged cost
/// refresh started an all-time scan (11 here) and every publication rewrote the widget snapshot (6 here).
@MainActor
@Suite(.serialized)
struct RefreshWorkCountTests {
    @Test
    func `unchanged cost refreshes start one all-time dashboard scan`() async throws {
        let fixture = try SpendDashboardFreshnessFixture()
        defer { fixture.cleanup() }
        fixture.installSyntheticLoader()
        await fixture.store.refreshSpendDashboardTokenUsageNow(for: .claude, force: true)
        let refreshes = 10
        for _ in 0..<refreshes {
            await fixture.store.refreshTokenUsageNow(for: .claude, force: true)
            _ = await fixture.request()
        }
        let regular = fixture.requests.count(where: { $0 == 30 })
        let allTime = fixture.requests.count(where: { $0 == SpendDashboardSource.scanDays })
        #expect(regular == refreshes)
        // One initial scan plus one for the first regular publication; the nine unchanged rescans add none.
        #expect(allTime == 2)
    }

    @Test
    func `unchanged publications write the widget snapshot once`() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefreshWorkCountTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings = testSettingsStore(suiteName: "RefreshWorkCountTests-\(UUID().uuidString)")
        settings.providerDetectionCompleted = true
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:],
            widgetSnapshotURL: url,
            widgetTimelineReloader: {})
        let publications = 6
        var writes = 0
        var lastFileNumber: Int?
        for _ in 0..<publications {
            store.persistWidgetSnapshot(reason: "test")
            await store.widgetSnapshotPersistTask?.value
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.intValue
            if fileNumber != nil, fileNumber != lastFileNumber {
                writes += 1
                lastFileNumber = fileNumber
            }
        }
        #expect(writes == 1)
    }
}
