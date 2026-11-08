import Foundation
import Testing
@testable import SharinganCore

struct SharinganCoreResourcesPortableTests {
    @Test(arguments: ["bundle", "resources"])
    func `direct and symlink executables resolve the same adjacent resources`(pathExtension: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharinganCoreResourcesPortableTests-\(UUID().uuidString)")
        let physicalDirectory = root.appendingPathComponent("physical", isDirectory: true)
        let symlinkDirectory = root.appendingPathComponent("links", isDirectory: true)
        try FileManager.default.createDirectory(at: physicalDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlinkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let executableURL = physicalDirectory.appendingPathComponent("SharinganCLI")
        try Data().write(to: executableURL)

        let sourceBundle = try #require(SharinganCoreResources.bundle)
        let resourceURL = physicalDirectory.appendingPathComponent("Sharingan_SharinganCore.\(pathExtension)")
        try FileManager.default.copyItem(
            at: sourceBundle.bundleURL.resolvingSymlinksInPath(),
            to: resourceURL)

        let symlinkURL = symlinkDirectory.appendingPathComponent("sharingan")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: executableURL)

        let directBundle = try #require(SharinganCoreResources.resolve(
            mainBundle: .main,
            executableURL: executableURL,
            swiftPMBuildDirectory: nil))
        let symlinkBundle = try #require(SharinganCoreResources.resolve(
            mainBundle: .main,
            executableURL: symlinkURL,
            swiftPMBuildDirectory: nil))

        let expectedPath = Self.canonicalPathComponents(resourceURL)
        #expect(Self.canonicalPathComponents(directBundle.bundleURL) == expectedPath)
        #expect(Self.canonicalPathComponents(symlinkBundle.bundleURL) == expectedPath)
    }

    private static func canonicalPathComponents(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }
}
