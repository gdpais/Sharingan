import Testing
@testable import SharinganCLI
@testable import SharinganCore

struct DeepSeekSourceModeTests {
    @Test
    func `Auto with an API key passes the Linux web support gate`() async {
        #expect(await !SharinganCLI.sourceModeRequiresWebSupport(
            .auto, provider: .deepseek, environment: ["DEEPSEEK_API_KEY": "synthetic-api-key"]))
        #expect(await !SharinganCLI.sourceModeRequiresWebSupport(
            .auto, provider: .deepseek, environment: ["DEEPSEEK_KEY": "synthetic-api-key"]))
        #expect(await SharinganCLI.sourceModeRequiresWebSupport(
            .auto, provider: .deepseek, environment: [:]))
        #expect(await SharinganCLI.sourceModeRequiresWebSupport(
            .auto, provider: .deepseek, environment: ["DEEPSEEK_API_KEY": " \n "]))
        #expect(await SharinganCLI.sourceModeRequiresWebSupport(
            .web, provider: .deepseek, environment: ["DEEPSEEK_API_KEY": "synthetic-api-key"]))
        #expect(await !SharinganCLI.sourceModeRequiresWebSupport(.api, provider: .deepseek, environment: [:]))
    }
}

extension SharinganCLI {
    static func sourceModeRequiresWebSupport(
        _ sourceMode: ProviderSourceMode,
        provider: UsageProvider,
        environment: [String: String]? = nil,
        settings: ProviderSettingsSnapshot? = nil) async -> Bool
    {
        let env = environment ?? [:]
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let context = ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: settings,
            fetcher: UsageFetcher(environment: env),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
        return await self.sourceModeRequiresWebSupport(provider: provider, context: context)
    }
}
