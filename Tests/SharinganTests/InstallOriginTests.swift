import Foundation
import Testing
@testable import Sharingan

struct InstallOriginTests {
    @Test
    func `detects legacy caskroom paths`() {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let app = URL(fileURLWithPath: "\(prefix)/Caskroom/sharingan/1.0.0/Sharingan.app")
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: []))
        }
    }

    @Test(arguments: [
        ("com.steipete.codexbar", true),
        ("com.gdpais.sharingan", false),
        ("com.gdpais.sharingan.debug", false),
        ("com.steipete.codexbar.debug", false),
    ])
    func `only the upstream bundle is managed by the sharingan cask`(bundleIdentifier: String, expected: Bool) {
        let app = URL(fileURLWithPath: "/opt/homebrew/Caskroom/sharingan/1.0.0/Sharingan.app")

        #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: []))
        #expect(InstallOrigin.isUpstreamHomebrewCask(
            appBundleURL: app,
            bundleIdentifier: bundleIdentifier,
            caskroomURLs: []) == expected)
    }

    @Test
    func `a missing bundle identifier is never managed by the sharingan cask`() {
        let app = URL(fileURLWithPath: "/usr/local/Caskroom/sharingan/1.0.0/Sharingan.app")

        #expect(!InstallOrigin.isUpstreamHomebrewCask(appBundleURL: app, bundleIdentifier: nil, caskroomURLs: []))
    }

    @Test
    func `Sharingan linked from the sharingan caskroom is not managed by Homebrew`() throws {
        try self.withFixture { root, app, artifact in
            try FileManager.default.createSymbolicLink(at: artifact, withDestinationURL: app)
            let caskrooms = [root.appendingPathComponent("brew/Caskroom")]

            #expect(InstallOrigin.isUpstreamHomebrewCask(
                appBundleURL: app,
                bundleIdentifier: InstallOrigin.upstreamCaskBundleIdentifier,
                caskroomURLs: caskrooms))
            #expect(!InstallOrigin.isUpstreamHomebrewCask(
                appBundleURL: app,
                bundleIdentifier: "com.gdpais.sharingan",
                caskroomURLs: caskrooms))
        }
    }

    @Test
    func `unrelated caskroom directory does not claim the app`() {
        #expect(!InstallOrigin.isHomebrewCask(
            appBundleURL: URL(fileURLWithPath: "/example/Caskroom/other/1.0/Sharingan.app"), caskroomURLs: []))
    }

    @Test(arguments: [false, true])
    func `matches the installed app through absolute or relative artifact links`(relative: Bool) throws {
        try self.withFixture { root, app, artifact in
            let destination = relative ? "../../../../Applications/Sharingan.app" : app.path
            try FileManager.default.createSymbolicLink(atPath: artifact.path, withDestinationPath: destination)
            let alias = root.appendingPathComponent("Alias.app")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: app)
            let other = root.appendingPathComponent("Other/Sharingan.app")
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            let caskrooms = [root.appendingPathComponent("missing"), root.appendingPathComponent("brew/Caskroom")]

            #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: alias, caskroomURLs: caskrooms))
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: other, caskroomURLs: caskrooms))
        }
    }

    @Test
    func `requires an artifact link rather than just a caskroom or backup directory`() throws {
        try self.withFixture { root, app, artifact in
            #expect(!InstallOrigin.isHomebrewCask(
                appBundleURL: app, caskroomURLs: [root.appendingPathComponent("missing")]))
            let caskrooms = [root.appendingPathComponent("brew/Caskroom")]
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
            try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
        }
    }

    @Test
    func `ignores dangling links while checking the remaining versions`() throws {
        try self.withFixture { root, app, artifact in
            let missing = root.appendingPathComponent("Missing.app")
            try FileManager.default.createSymbolicLink(at: artifact, withDestinationURL: missing)
            let caskrooms = [root.appendingPathComponent("brew/Caskroom")]
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: missing, caskroomURLs: caskrooms))
            #expect(!InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))

            let current = artifact.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("0.60.1/Sharingan.app")
            try FileManager.default.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: current, withDestinationURL: app)
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: app, caskroomURLs: caskrooms))
        }
    }

    @Test
    func `legacy caskroom apps still check for competing prefix claims`() throws {
        try self.withFixture { root, _, artifact in
            let manager = FileManager.default
            try manager.createDirectory(at: artifact, withIntermediateDirectories: true)
            let owner = root.appendingPathComponent("brew")
            let samePrefix = owner.appendingPathComponent("Caskroom/sharingan/0.60.0/Sharingan.app")
            try manager.createDirectory(at: samePrefix.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createSymbolicLink(at: samePrefix, withDestinationURL: artifact)
            let caskrooms = [owner.appendingPathComponent("Caskroom"), root.appendingPathComponent("other/Caskroom")]
            #expect(InstallOrigin.homebrewPrefix(appBundleURL: artifact, caskroomURLs: caskrooms)
                == owner.resolvingSymlinksInPath().standardizedFileURL)

            let competing = caskrooms[1].appendingPathComponent("sharingan/0.58.0/Sharingan.app")
            try manager.createDirectory(at: competing.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createSymbolicLink(at: competing, withDestinationURL: artifact)
            #expect(InstallOrigin.isHomebrewCask(appBundleURL: artifact, caskroomURLs: caskrooms))
            #expect(InstallOrigin.homebrewPrefix(appBundleURL: artifact, caskroomURLs: caskrooms) == nil)
        }
    }

    private func withFixture(_ body: (_ root: URL, _ app: URL, _ artifact: URL) throws -> Void) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let app = root.appendingPathComponent("Applications/Sharingan.app")
        let artifact = root.appendingPathComponent("brew/Caskroom/sharingan/0.59.0/Sharingan.app")
        try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body(root, app, artifact)
    }
}
