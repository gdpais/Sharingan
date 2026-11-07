import CodexBarCore
import Foundation
import Testing
@testable import CodexBarWidget

/// Widgets classify lanes with the same Core bands as the menu, read from the snapshot the app writes.
struct WidgetSeverityBandsTests {
    private static let updatedAt = Date(timeIntervalSince1970: 1_782_000_000)

    private func entry(severityBands: QuotaSeverityBandSet? = nil) -> WidgetSnapshot.ProviderEntry {
        var entry = WidgetSnapshot.ProviderEntry(
            provider: .gemini,
            updatedAt: Self.updatedAt,
            primary: nil,
            secondary: nil,
            usageRows: [
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "primary", title: "Session", percentLeft: 25),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "secondary", title: "Weekly", percentLeft: 60),
                WidgetSnapshot.WidgetUsageRowSnapshot(id: "tertiary", title: "Monthly", percentLeft: 8),
            ])
        entry.severityBands = severityBands
        return entry
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test
    func `snapshots without bands decode and keep the standard callout`() throws {
        let snapshot = WidgetSnapshot(entries: [self.entry()], generatedAt: Self.updatedAt)
        let data = try Self.encoder.encode(snapshot)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("severityBands"))

        let decoded = try Self.decoder.decode(WidgetSnapshot.self, from: data)
        let entry = try #require(decoded.entries.first)
        #expect(entry.severityBands == nil)

        let lanes = WidgetTileLane.lanes(for: entry)
        #expect(lanes.allSatisfy { $0.severityBands == .standard })
        let tertiary = try #require(lanes.first { $0.id == "tertiary" })
        #expect(QuotaSeverity.isLow(remaining: tertiary.remainingPercent, bands: tertiary.severityBands))
        let session = try #require(lanes.first { $0.id == "primary" })
        #expect(!QuotaSeverity.isLow(remaining: session.remainingPercent, bands: session.severityBands))
    }

    @Test
    func `snapshots with bands round trip and drive each lane`() throws {
        let bands = QuotaSeverityBandSet(
            session: .from(thresholds: [40, 30]),
            weekly: .from(thresholds: [75, 65]),
            lanes: [QuotaWarningLaneID.tertiary: .from(thresholds: [5, 3])])
        let snapshot = WidgetSnapshot(entries: [self.entry(severityBands: bands)], generatedAt: Self.updatedAt)

        let decoded = try Self.decoder.decode(WidgetSnapshot.self, from: Self.encoder.encode(snapshot))
        let entry = try #require(decoded.entries.first)
        #expect(entry.severityBands == bands)

        let lanes = WidgetTileLane.lanes(for: entry)
        let levels = Dictionary(uniqueKeysWithValues: lanes.compactMap { lane in
            lane.remainingPercent.map { (lane.id, lane.severityBands.level(remainingPercent: $0)) }
        })
        #expect(levels["primary"] == .critical)
        #expect(levels["secondary"] == .critical)
        #expect(levels["tertiary"] == .normal)
        #expect(lanes.filter { QuotaSeverity.isLow(remaining: $0.remainingPercent, bands: $0.severityBands) }
            .map(\.id) == ["primary", "secondary"])
    }

    @Test
    func `account entries decode older payloads without bands`() throws {
        let payload = """
        {"id":"acct","provider":"gemini","label":"Personal","usage":{"provider":"gemini",\
        "updatedAt":"2026-06-01T00:00:00Z","dailyUsage":[]}}
        """
        let account = try Self.decoder.decode(WidgetSnapshot.AccountEntry.self, from: Data(payload.utf8))
        #expect(account.usage?.severityBands == nil)
    }

    @Test
    func `widget severity keeps the historical defaults`() {
        #expect(QuotaSeverity.level(remaining: nil) == nil)
        #expect(QuotaSeverity.level(remaining: 50) == .warning)
        #expect(QuotaSeverity.isLow(remaining: 10))
        #expect(!QuotaSeverity.isLow(remaining: 10.1))
        #expect(QuotaSeverity.isLow(remaining: 0))
        let early = QuotaSeverityBands.from(thresholds: [60, 40])
        #expect(QuotaSeverity.isLow(remaining: 40, bands: early))
        #expect(!QuotaSeverity.isLow(remaining: 41, bands: early))
    }
}
