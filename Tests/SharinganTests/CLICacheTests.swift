import Commander
import Testing
@testable import SharinganCLI

struct CLICacheTests {
    @Test
    func `cache clear parses cookies provider flags`() throws {
        let parser = CommandParser(signature: SharinganCLI._cacheSignatureForTesting())
        let parsed = try parser.parse(arguments: ["--cookies", "--provider", "claude", "--json"])

        #expect(parsed.flags.contains("cookies"))
        #expect(parsed.flags.contains("jsonShortcut"))
        #expect(parsed.options["provider"] == ["claude"])
        #expect(SharinganCLI._decodeFormatForTesting(from: parsed) == .json)
    }

    @Test
    func `provider scope is rejected for cost clearing`() {
        #expect(SharinganCLI.cacheClearProviderScopeError(rawProvider: nil, clearCost: true) == nil)
        #expect(SharinganCLI.cacheClearProviderScopeError(rawProvider: "claude", clearCost: false) == nil)
        #expect(SharinganCLI.cacheClearProviderScopeError(rawProvider: "claude", clearCost: true)?
            .contains("--provider only scopes cookie caches") == true)
    }

    @Test
    func `cache help documents provider as cookie scoped`() {
        let help = SharinganCLI.cacheHelp(version: "0.0.0")

        #expect(help.contains("--provider with --cookies"))
        #expect(help.contains("sharingan cache clear --cookies --provider claude"))
    }
}
