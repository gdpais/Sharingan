import Commander
import Foundation
import SharinganCore

struct CLIUsageFetchSetup {
    let tokenSelection: TokenAccountCLISelection
    let includeStatus: Bool
    let command: UsageCommandContext

    init(
        values: ParsedValues,
        providers: [UsageProvider],
        output: CLIOutputPreferences,
        cardsLayout: Bool = false) throws
    {
        let sourceMode = SharinganCLI.decodeSourceMode(from: values)
        if values.options["source"]?.last != nil, sourceMode == nil {
            throw CLIArgumentError("--source must be auto|web|cli|oauth|api.")
        }
        let webTimeout = try SharinganCLI.decodeWebTimeout(from: values) ?? 60
        let selection = try SharinganCLI.decodeTokenAccountSelection(from: values)
        if selection.allAccounts, selection.label != nil || selection.index != nil {
            throw CLIArgumentError("--all-accounts cannot be combined with --account or --account-index.")
        }
        let appAutoVerifier = !cardsLayout && values.flags.contains("appAutoVerifier")
        if let message = SharinganCLI.appAutoVerifierArgumentError(
            enabled: appAutoVerifier,
            providers: providers,
            sourceMode: sourceMode,
            tokenSelection: selection)
        {
            throw CLIArgumentError(message)
        }
        if let message = selection.providerSelectionError(providers) {
            throw CLIArgumentError(message)
        }
        self.tokenSelection = selection
        self.includeStatus = values.flags.contains("status")
        let format: OutputFormat = cardsLayout ? .text : output.format
        let browserDetection = BrowserDetection()
        self.command = UsageCommandContext(
            format: format,
            includeCredits: format == .json || !values.flags.contains("noCredits"),
            sourceModeOverride: sourceMode,
            antigravityPlanDebug: values.flags.contains("antigravityPlanDebug"),
            augmentDebug: values.flags.contains("augmentDebug"),
            webDebugDumpHTML: values.flags.contains("webDebugDumpHtml"),
            webTimeout: webTimeout,
            verbose: values.flags.contains("verbose"),
            useColor: SharinganCLI.shouldUseColor(noColor: values.flags.contains("noColor"), format: format),
            resetStyle: SharinganCLI.resetTimeDisplayStyleFromDefaults(),
            weeklyWorkDays: SharinganCLI.weeklyProgressWorkDaysFromDefaults(),
            jsonOnly: output.jsonOnly,
            includeAllCodexAccounts: selection.allAccounts && providers == [.codex],
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            providerRuntime: appAutoVerifier ? .app : .cli,
            cardsLayout: cardsLayout)
    }

    func tokenContext(config: SharinganConfig, output: CLIOutputPreferences) -> TokenAccountCLIContext {
        do {
            return try TokenAccountCLIContext(
                selection: self.tokenSelection,
                config: config,
                verbose: self.command.verbose,
                resolutionScope: self.command.providerRuntime == .app ? .ambientAccount : .configuredAccounts)
        } catch {
            SharinganCLI.exit(
                code: .failure,
                message: "Error: \(error.localizedDescription)",
                output: output,
                kind: .config)
        }
    }
}

extension SharinganCLI {
    static func usageFetchSetup(
        values: ParsedValues,
        providers: [UsageProvider],
        output: CLIOutputPreferences,
        cardsLayout: Bool = false) -> CLIUsageFetchSetup
    {
        do {
            return try CLIUsageFetchSetup(
                values: values,
                providers: providers,
                output: output,
                cardsLayout: cardsLayout)
        } catch {
            exit(code: .failure, message: "Error: \(error.localizedDescription)", output: output, kind: .args)
        }
    }
}
