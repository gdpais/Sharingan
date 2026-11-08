import Foundation
import Testing
@testable import CodexBarCore

/// Sharingan must never share runtime state with a CodexBar install on the same Mac.
struct AppIdentityTests {
    @Test
    func `runtime identifiers never reuse CodexBar names`() {
        let identifiers = [
            AppIdentity.reverseDNS,
            AppIdentity.supportDirectoryName,
            AppIdentity.configDirectoryName,
            AppIdentity.homeDotDirectoryName,
            AppIdentity.configPathEnvironmentKey,
            AppIdentity.keychainService,
            AppIdentity.keychainCacheService,
            AppIdentity.keychainCacheLabel,
            AppIdentity.iCloudContainerIdentifier,
            AppIdentity.cliCommandName,
            AppGroupSupport.currentGroupID(teamID: "ABCDE12345", bundleID: AppDefaultsDomain.release),
            AppGroupSupport.legacyGroupID(for: AppDefaultsDomain.release),
        ]
        for identifier in identifiers {
            #expect(!identifier.lowercased().contains("codexbar"), "\(identifier)")
            #expect(!identifier.lowercased().contains("steipete"), "\(identifier)")
        }
    }

    @Test
    func `config path ignores CODEXBAR_CONFIG and uses the Sharingan folders`() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharingan-identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let defaultURL = CodexBarConfigStore.defaultURL(
            home: home,
            environment: ["CODEXBAR_CONFIG": "/tmp/codexbar/config.json"])
        #expect(defaultURL.path == home.appendingPathComponent(".config/sharingan/config.json").path)

        let overridden = CodexBarConfigStore.defaultURL(
            home: home,
            environment: ["SHARINGAN_CONFIG": "/tmp/sharingan-override.json"])
        #expect(overridden.path == "/tmp/sharingan-override.json")

        // An existing CodexBar config must not be picked up as Sharingan's legacy config.
        let codexBarLegacy = home.appendingPathComponent(".codexbar/config.json")
        try FileManager.default.createDirectory(
            at: codexBarLegacy.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: codexBarLegacy)
        let withCodexBarInstalled = CodexBarConfigStore.defaultURL(home: home, environment: [:])
        #expect(withCodexBarInstalled.path == home.appendingPathComponent(".config/sharingan/config.json").path)
    }
}
