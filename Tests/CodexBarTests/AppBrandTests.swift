import Foundation
import Testing
@testable import CodexBar

struct AppBrandTests {
    @Test
    func `app name and project links point at the Sharingan fork`() throws {
        #expect(AppBrand.displayName == "Sharingan")
        let repository = try #require(URL(string: AppBrand.repositoryURL))
        #expect(repository.host == "github.com")
        #expect(repository.path == "/gdpais/Sharingan")
        let readme = try #require(URL(string: AppBrand.readmeURL))
        #expect(readme.absoluteString.hasPrefix(AppBrand.repositoryURL + "/"))
    }

    @Test
    func `upstream credit names CodexBar and links its repository`() throws {
        let upstream = try #require(URL(string: AppBrand.upstreamRepositoryURL))
        #expect(upstream.host == "github.com")
        #expect(upstream.path == "/steipete/CodexBar")
        #expect(AppBrand.upstreamCreditKey.contains(AppBrand.upstreamName))
        #expect(AppBrand.upstreamCreditKey.contains(AppBrand.upstreamAuthor))
    }

    @Test
    func `upstream credit falls back to its English text`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(L(AppBrand.upstreamCreditKey) == "Based on CodexBar by Peter Steinberger")
        }
    }

    @Test
    func `about pane wires the fork repository and upstream credit`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexBar/Settings/PreferencesAboutPane.swift"),
            encoding: .utf8)
        #expect(source.contains("url: AppBrand.repositoryURL"))
        #expect(source.contains("title: L(AppBrand.upstreamCreditKey)"))
        #expect(source.contains("url: AppBrand.upstreamRepositoryURL"))
        #expect(source.contains("Text(AppBrand.displayName)"))
        #expect(!source.contains("\"https://github.com/steipete/CodexBar\""))
    }
}
