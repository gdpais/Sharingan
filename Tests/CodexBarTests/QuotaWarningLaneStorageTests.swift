import Foundation
import Testing
@testable import CodexBarCore

/// Lane overrides are stored as the provider-level key `quotaWarningWindows`, which builds that predate lanes
/// (upstream CodexBar reads the same config) keep through their own rewrites.
struct QuotaWarningLaneStorageTests {
    private static let lanes = [
        QuotaWarningLaneID.tertiary: QuotaWarningWindowConfig(thresholds: [30, 10], enabled: true),
    ]

    @Test
    func `lane overrides are written at the provider level and read back`() throws {
        let warnings = QuotaWarningConfig(weekly: QuotaWarningWindowConfig(thresholds: [40]), windows: Self.lanes)
        let config = ProviderConfig(id: UsageProvider.gemini.instanceID, quotaWarnings: warnings)

        let record = try Self.record(JSONEncoder().encode(config))
        let nested = try #require(record["quotaWarnings"] as? [String: Any])
        #expect(nested["weekly"] != nil)
        #expect(nested["windows"] == nil)
        #expect(record["quotaWarningWindows"] != nil)

        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.quotaWarnings == warnings)
    }

    @Test
    func `a config holding only lane overrides writes no nested quota warnings`() throws {
        let config = ProviderConfig(
            id: UsageProvider.gemini.instanceID,
            quotaWarnings: QuotaWarningConfig(windows: Self.lanes))

        let record = try Self.record(JSONEncoder().encode(config))
        #expect(record["quotaWarnings"] == nil)
        #expect(record["quotaWarningWindows"] != nil)

        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.quotaWarnings == QuotaWarningConfig(windows: Self.lanes))
    }

    @Test
    func `configs without lane overrides encode as before`() throws {
        let warnings = QuotaWarningConfig(session: QuotaWarningWindowConfig(thresholds: [80, 50, 30, 10]))
        let config = ProviderConfig(id: UsageProvider.gemini.instanceID, quotaWarnings: warnings)

        let record = try Self.record(JSONEncoder().encode(config))
        #expect(record["quotaWarningWindows"] == nil)
        #expect((record["quotaWarnings"] as? [String: Any])?["session"] != nil)
        #expect(try JSONDecoder().decode(ProviderConfig.self, from: JSONEncoder().encode(config)).quotaWarnings
            == warnings)
    }

    @Test
    func `nested lane overrides from an earlier build are read and the next save moves them`() throws {
        let legacy = Data("""
        {"id":"gemini","quotaWarnings":{"weekly":{"thresholds":[40]},\
        "windows":{"tertiary":{"thresholds":[30,10],"enabled":true}}}}
        """.utf8)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: legacy)
        #expect(decoded.quotaWarnings?.windows == Self.lanes)

        let record = try Self.record(JSONEncoder().encode(decoded))
        #expect((record["quotaWarnings"] as? [String: Any])?["windows"] == nil)
        #expect(record["quotaWarningWindows"] != nil)
    }

    @Test
    func `the provider level key wins over a nested copy`() throws {
        let both = Data("""
        {"id":"gemini","quotaWarnings":{"windows":{"tertiary":{"thresholds":[70]}}},\
        "quotaWarningWindows":{"tertiary":{"thresholds":[30,10],"enabled":true}}}
        """.utf8)
        let decoded = try JSONDecoder().decode(ProviderConfig.self, from: both)
        #expect(decoded.quotaWarnings?.windows == Self.lanes)
    }

    @Test
    func `an upstream style rewrite keeps the lane overrides`() throws {
        let warnings = QuotaWarningConfig(weekly: QuotaWarningWindowConfig(thresholds: [40]), windows: Self.lanes)
        let config = ProviderConfig(id: UsageProvider.gemini.instanceID, quotaWarnings: warnings)

        let rewritten = try Self.upstreamRewrite(JSONEncoder().encode(config))
        #expect(try JSONDecoder().decode(ProviderConfig.self, from: rewritten).quotaWarnings == warnings)

        // The nested layout this replaces does not survive the same rewrite.
        let nested = Data(#"{"id":"gemini","quotaWarnings":{"windows":{"tertiary":{"thresholds":[30]}}}}"#.utf8)
        let nestedRewritten = try Self.upstreamRewrite(nested)
        #expect(try JSONDecoder().decode(ProviderConfig.self, from: nestedRewritten).quotaWarnings?.windows == nil)
    }

    @Test
    func `the config file path stores lane overrides at the provider level`() throws {
        let data = Data("""
        {"version":\(CodexBarConfig.currentVersion),"providers":[{"id":"gemini",\
        "quotaWarnings":{"windows":{"tertiary":{"thresholds":[30,10],"enabled":true}}}}]}
        """.utf8)
        let config = try CodexBarConfig.decode(from: data)
        #expect(config.providerConfig(for: UsageProvider.gemini.instanceID)?.quotaWarnings?.windows == Self.lanes)

        let saved = try JSONSerialization.jsonObject(with: config.encodedData()) as? [String: Any]
        let providers = try #require(saved?["providers"] as? [[String: Any]])
        let gemini = try #require(providers.first { $0["id"] as? String == "gemini" })
        #expect(gemini["quotaWarnings"] == nil)
        #expect(gemini["quotaWarningWindows"] != nil)

        let reloaded = try CodexBarConfig.decode(from: config.encodedData())
        #expect(reloaded.providerConfig(for: UsageProvider.gemini.instanceID)?.quotaWarnings?.windows == Self.lanes)
    }

    // MARK: - Helpers

    private static func record(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Decodes and re-encodes one provider record the way upstream CodexBar does.
    private static func upstreamRewrite(_ data: Data) throws -> Data {
        try JSONEncoder().encode(JSONDecoder().decode(UpstreamProviderRecord.self, from: data))
    }
}

/// Upstream CodexBar's reading of one provider record: `quotaWarnings` through its synthesized type, which knows
/// only `session` and `weekly`, and every other key kept as an opaque value that is written back unchanged.
private struct UpstreamProviderRecord: Codable {
    struct QuotaWarnings: Codable {
        var session: QuotaWarningWindowConfig?
        var weekly: QuotaWarningWindowConfig?
    }

    private static var quotaWarningsKey: ProviderConfigCodingKey {
        ProviderConfigCodingKey("quotaWarnings")
    }

    var quotaWarnings: QuotaWarnings?
    var others: [String: ProviderConfigExtensionValue]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: ProviderConfigCodingKey.self)
        self.quotaWarnings = try container.decodeIfPresent(QuotaWarnings.self, forKey: Self.quotaWarningsKey)
        var others: [String: ProviderConfigExtensionValue] = [:]
        for key in container.allKeys where key.stringValue != Self.quotaWarningsKey.stringValue {
            others[key.stringValue] = try container.decode(ProviderConfigExtensionValue.self, forKey: key)
        }
        self.others = others
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ProviderConfigCodingKey.self)
        try container.encodeIfPresent(self.quotaWarnings, forKey: Self.quotaWarningsKey)
        for (key, value) in self.others {
            try container.encode(value, forKey: ProviderConfigCodingKey(key))
        }
    }
}
