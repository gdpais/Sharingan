import Foundation
import Testing
@testable import SharinganCLI
@testable import SharinganCore

struct SharinganConfigStoreEmptyTests {
    @Test(arguments: [nil, "", " \t\r\n "] as [String?])
    func `missing and blank configs load as absent without writing`(_ contents: String?) throws {
        let fixture = try Fixture(contents)
        defer { fixture.remove() }

        #expect(try fixture.store.load() == nil)
        let snapshot = try SharinganCLI.loadServeConfigSnapshot(configStore: fixture.store)
        #expect(try snapshot.config.encodedData() == SharinganConfig.makeDefault().encodedData())
        #expect(try fixture.contents() == contents.map { Data($0.utf8) })
    }

    @Test(arguments: [nil, "", " \t\r\n "] as [String?])
    func `default creation and subsequent settings save produce private valid JSON`(_ contents: String?) throws {
        let fixture = try Fixture(contents)
        defer { fixture.remove() }

        var config = try fixture.store.loadOrCreateDefault()
        #expect(try config.encodedData() == SharinganConfig.makeDefault().encodedData())
        config.setProviderConfig(ProviderConfig(id: .grok, enabled: true))
        try fixture.store.save(config)
        #expect(try fixture.store.load()?.providerConfig(for: .grok)?.enabled == true)
        let data = try #require(try fixture.contents())
        #expect(try SharinganConfig.decode(from: data).encodedData() == config.encodedData())
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test(arguments: ["{", " \n{\"providers\":", "null", "garbage", "\u{0000}"])
    func `nonempty malformed configs still fail closed and retain their bytes`(_ contents: String) throws {
        let fixture = try Fixture(contents)
        defer { fixture.remove() }

        #expect(throws: SharinganConfigStoreError.self) { try fixture.store.load() }
        #expect(throws: SharinganConfigStoreError.self) { try fixture.store.loadOrCreateDefault() }
        #expect(throws: SharinganConfigStoreError.self) {
            try SharinganCLI.loadServeConfigSnapshot(configStore: fixture.store)
        }
        #expect(try fixture.contents() == Data(contents.utf8))
    }

    private struct Fixture {
        let directory: URL
        let store: SharinganConfigStore

        init(_ contents: String?) throws {
            self.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.store = SharinganConfigStore(fileURL: self.directory.appendingPathComponent("config.json"))
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if let contents { try Data(contents.utf8).write(to: self.store.fileURL) }
        }

        func contents() throws -> Data? {
            guard FileManager.default.fileExists(atPath: self.store.fileURL.path) else { return nil }
            return try Data(contentsOf: self.store.fileURL)
        }

        func remove() { try? FileManager.default.removeItem(at: self.directory) }
    }
}
