import AppIntents
import SharinganCore
import SwiftUI
import WidgetKit

/// Every built-in provider, so a configured widget can show any provider the app publishes. The first twenty
/// cases are the original picker set; their raw values are what saved widgets store, so they never change.
/// `WidgetProviderOptions` narrows the picker to providers with data in the latest snapshot.
enum ProviderChoice: String, AppEnum {
    case codex
    case claude
    case gemini
    case alibaba
    case alibabatokenplan
    case qwencloud
    case antigravity
    case cursor
    case zai
    case copilot
    case devin
    case minimax
    case kilo
    case opencode
    case opencodego
    case mistral
    case kimi
    case deepseek
    case openrouter
    case pi
    case openai
    case azureopenai
    case clinepass
    case factory
    case fireworks
    case manus
    case kiro
    case vertexai
    case augment
    case jetbrains
    case moonshot
    case amp
    case t3chat
    case langdock
    case ollama
    case synthetic
    case elevenlabs
    case warp
    case windsurf
    case zed
    case perplexity
    case mimo
    case doubao
    case sakana
    case abacus
    case deepinfra
    case codebuff
    case venice
    case commandcode
    case qoder
    case stepfun
    case bedrock
    case grok
    case groq
    case llmproxy
    case litellm
    case bifrost
    case aixy
    case deepgram
    case soniox
    case poe
    case chutes
    case neuralwatt
    case helmcode
    case clawrouter
    case longcat
    case sub2api
    case wayfinder
    case zenmux
    case aiand
    case zoommate
    case xai
    case xapi
    case notion
    case ibmbob
    case nous
    case muse
    case coderabbit
    case replicate
    case huggingface
    case raycast
    case v0
    case typesafe
    case hyper
    case gitkraken
    case futureagi
    case devpass
    case atlascloud
    case vercel
    case llmman
    case xkiro
    case museai
    case lithosai
    case workbuddy
    case tavily
    case linkup
    case tinyapi
    case exa
    case cosmic
    case aerostack
    case sailresearch
    case sofya
    case fal
    case flora
    case parallel
    case claudeplatform
    case munito
    case traecn
    case chatbox
    case abliteration

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")

    /// AppIntents extracts this metadata statically; it must stay a literal, exhaustive
    /// dictionary. WidgetProviderChoiceTests pins these titles to the descriptor registry.
    /// Provider-specific by design: AppIntents requires a compile-time provider display inventory.
    static let caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .codex: DisplayRepresentation(title: "Codex"),
        .claude: DisplayRepresentation(title: "Claude"),
        .gemini: DisplayRepresentation(title: "Gemini"),
        .alibaba: DisplayRepresentation(title: "Alibaba"),
        .alibabatokenplan: DisplayRepresentation(title: "Alibaba Token Plan"),
        .qwencloud: DisplayRepresentation(title: "Qwen Cloud"),
        .antigravity: DisplayRepresentation(title: "Antigravity"),
        .cursor: DisplayRepresentation(title: "Cursor"),
        .zai: DisplayRepresentation(title: "z.ai / GLM"),
        .copilot: DisplayRepresentation(title: "Copilot"),
        .devin: DisplayRepresentation(title: "Devin"),
        .minimax: DisplayRepresentation(title: "MiniMax"),
        .kilo: DisplayRepresentation(title: "Kilo"),
        .opencode: DisplayRepresentation(title: "OpenCode"),
        .opencodego: DisplayRepresentation(title: "OpenCode Go"),
        .mistral: DisplayRepresentation(title: "Mistral"),
        .kimi: DisplayRepresentation(title: "Kimi Code"),
        .deepseek: DisplayRepresentation(title: "DeepSeek"),
        .openrouter: DisplayRepresentation(title: "OpenRouter"),
        .pi: DisplayRepresentation(title: "Pi"),
        .openai: DisplayRepresentation(title: "OpenAI"),
        .azureopenai: DisplayRepresentation(title: "Azure OpenAI"),
        .clinepass: DisplayRepresentation(title: "ClinePass"),
        .factory: DisplayRepresentation(title: "Droid"),
        .fireworks: DisplayRepresentation(title: "Fireworks"),
        .manus: DisplayRepresentation(title: "Manus"),
        .kiro: DisplayRepresentation(title: "Kiro"),
        .vertexai: DisplayRepresentation(title: "Vertex AI"),
        .augment: DisplayRepresentation(title: "Augment"),
        .jetbrains: DisplayRepresentation(title: "JetBrains AI"),
        .moonshot: DisplayRepresentation(title: "Moonshot / Kimi Open Platform"),
        .amp: DisplayRepresentation(title: "Amp"),
        .t3chat: DisplayRepresentation(title: "T3 Chat"),
        .langdock: DisplayRepresentation(title: "Langdock"),
        .ollama: DisplayRepresentation(title: "Ollama"),
        .synthetic: DisplayRepresentation(title: "Synthetic"),
        .elevenlabs: DisplayRepresentation(title: "ElevenLabs"),
        .warp: DisplayRepresentation(title: "Warp"),
        .windsurf: DisplayRepresentation(title: "Windsurf"),
        .zed: DisplayRepresentation(title: "Zed"),
        // Provider-specific by design: AppIntents requires literal catalog titles; snapshot data gates eligibility.
        .perplexity: DisplayRepresentation(title: "Perplexity"),
        .mimo: DisplayRepresentation(title: "Xiaomi MiMo"),
        .doubao: DisplayRepresentation(title: "Doubao"),
        .sakana: DisplayRepresentation(title: "Sakana AI"),
        .abacus: DisplayRepresentation(title: "Abacus AI"),
        .deepinfra: DisplayRepresentation(title: "DeepInfra"),
        .codebuff: DisplayRepresentation(title: "Codebuff"),
        .venice: DisplayRepresentation(title: "Venice"),
        .commandcode: DisplayRepresentation(title: "Command Code"),
        .qoder: DisplayRepresentation(title: "Qoder"),
        .stepfun: DisplayRepresentation(title: "StepFun"),
        .bedrock: DisplayRepresentation(title: "AWS Bedrock"),
        .grok: DisplayRepresentation(title: "Grok"),
        .groq: DisplayRepresentation(title: "Groq"),
        .llmproxy: DisplayRepresentation(title: "LLM Proxy"),
        .litellm: DisplayRepresentation(title: "LiteLLM"),
        .bifrost: DisplayRepresentation(title: "Bifrost"),
        .aixy: DisplayRepresentation(title: "Aixy"),
        .deepgram: DisplayRepresentation(title: "Deepgram"),
        .soniox: DisplayRepresentation(title: "Soniox"),
        .poe: DisplayRepresentation(title: "Poe"),
        .chutes: DisplayRepresentation(title: "Chutes"),
        .neuralwatt: DisplayRepresentation(title: "Neuralwatt"),
        .helmcode: DisplayRepresentation(title: "Helmcode"),
        .clawrouter: DisplayRepresentation(title: "ClawRouter"),
        .longcat: DisplayRepresentation(title: "LongCat"),
        .sub2api: DisplayRepresentation(title: "sub2api"),
        .wayfinder: DisplayRepresentation(title: "Wayfinder"),
        .zenmux: DisplayRepresentation(title: "ZenMux"),
        .aiand: DisplayRepresentation(title: "ai&"),
        .zoommate: DisplayRepresentation(title: "ZoomMate"),
        .xai: DisplayRepresentation(title: "xAI"),
        .xapi: DisplayRepresentation(title: "X API"),
        .notion: DisplayRepresentation(title: "Notion AI"),
        .ibmbob: DisplayRepresentation(title: "IBM Bob"),
        .nous: DisplayRepresentation(title: "Nous Portal"),
        .muse: DisplayRepresentation(title: "Muse Code"),
        .coderabbit: DisplayRepresentation(title: "CodeRabbit"),
        .replicate: DisplayRepresentation(title: "Replicate"),
        .huggingface: DisplayRepresentation(title: "Hugging Face"),
        // Provider-specific by design: AppIntents requires literal catalog titles; snapshot data gates eligibility.
        .raycast: DisplayRepresentation(title: "Raycast"),
        .v0: DisplayRepresentation(title: "v0"),
        .typesafe: DisplayRepresentation(title: "TypeSafe"),
        .hyper: DisplayRepresentation(title: "Charm Hyper"),
        .gitkraken: DisplayRepresentation(title: "GitKraken AI"),
        .futureagi: DisplayRepresentation(title: "Future AGI"),
        .devpass: DisplayRepresentation(title: "DevPass"),
        .atlascloud: DisplayRepresentation(title: "Atlas Cloud"),
        .vercel: DisplayRepresentation(title: "Vercel AI Gateway"),
        .llmman: DisplayRepresentation(title: "llmman"),
        .xkiro: DisplayRepresentation(title: "xKiro"),
        .museai: DisplayRepresentation(title: "Muse (muse.ai)"),
        .lithosai: DisplayRepresentation(title: "LithosAI"),
        .workbuddy: DisplayRepresentation(title: "WorkBuddy"),
        .tavily: DisplayRepresentation(title: "Tavily"),
        .linkup: DisplayRepresentation(title: "Linkup"),
        .tinyapi: DisplayRepresentation(title: "TinyApi"),
        .exa: DisplayRepresentation(title: "Exa"),
        .cosmic: DisplayRepresentation(title: "Cosmic AI"),
        .aerostack: DisplayRepresentation(title: "Aerostack"),
        .sailresearch: DisplayRepresentation(title: "Sail Research"),
        .sofya: DisplayRepresentation(title: "Sofya"),
        .fal: DisplayRepresentation(title: "fal"),
        .flora: DisplayRepresentation(title: "FLORA"),
        .parallel: DisplayRepresentation(title: "Parallel"),
        .claudeplatform: DisplayRepresentation(title: "Claude Platform"),
        .munito: DisplayRepresentation(title: "Munito"),
        .traecn: DisplayRepresentation(title: "Trae CN"),
        .chatbox: DisplayRepresentation(title: "Chatbox AI"),
        .abliteration: DisplayRepresentation(title: "abliteration.ai"),
    ]

    var provider: UsageProvider {
        UsageProvider(rawValue: self.rawValue)!
    }

    /// The original picker set, which the Switcher still pages through by default.
    init?(provider: UsageProvider) {
        guard ProviderDescriptorRegistry.descriptor(for: provider).metadata.widgetSelectable else { return nil }
        self.init(rawValue: provider.rawValue)
    }

    /// Any built-in provider, for pickers and switchers that are not limited to the original set.
    init?(catalogProvider provider: UsageProvider) {
        self.init(rawValue: provider.rawValue)
    }
}

enum CompactMetric: String, AppEnum {
    case credits
    case todayCost
    case last30DaysCost

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static let caseDisplayRepresentations: [CompactMetric: DisplayRepresentation] = [
        .credits: DisplayRepresentation(title: "Credits left"),
        .todayCost: DisplayRepresentation(title: "Today cost"),
        .last30DaysCost: DisplayRepresentation(title: "Cost"),
    ]
}

struct ProviderSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider"
    static let description = IntentDescription("Select the provider to display in the widget.")

    @Parameter(title: "Provider", default: .codex, optionsProvider: WidgetProviderOptions())
    var provider: ProviderChoice

    /// Display options added after release. Saved widgets read these defaults, which reproduce their output.
    @Parameter(title: "Metric", default: .automatic)
    var metric: WidgetUsageMetricChoice

    @Parameter(title: "Window", default: .automatic)
    var window: WidgetUsageWindowChoice

    @Parameter(title: "Range", default: .automatic)
    var range: WidgetHistoryRangeChoice

    init() {
        self.provider = .codex
        self.metric = .automatic
        self.window = .automatic
        self.range = .automatic
    }
}

struct SwitchWidgetProviderIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Provider"
    static let description = IntentDescription("Switch the provider shown in the widget.")

    @Parameter(title: "Provider")
    var provider: ProviderChoice

    init() {}

    init(provider: ProviderChoice) {
        self.provider = provider
    }

    func perform() async throws -> some IntentResult {
        WidgetSelectionStore.saveSelectedProvider(self.provider.provider)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompactMetricSelectionIntent: AppIntent, WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider + Metric"
    static let description = IntentDescription("Select the provider and metric to display.")

    @Parameter(title: "Provider", default: .codex, optionsProvider: WidgetProviderOptions())
    var provider: ProviderChoice

    @Parameter(title: "Metric", default: .credits)
    var metric: CompactMetric

    init() {
        self.provider = .codex
        self.metric = .credits
    }
}

struct SharinganWidgetEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let snapshot: WidgetSnapshot
    var options = WidgetUsageOptions()
}

struct SharinganCompactEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let metric: CompactMetric
    let snapshot: WidgetSnapshot
}

struct SharinganSwitcherEntry: TimelineEntry {
    let date: Date
    let provider: UsageProvider
    let availableProviders: [UsageProvider]
    let snapshot: WidgetSnapshot
}

struct SharinganTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SharinganWidgetEntry {
        SharinganWidgetEntry(
            date: Date(),
            provider: .codex,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> SharinganWidgetEntry {
        let provider = configuration.provider.provider
        return SharinganWidgetEntry(
            date: Date(),
            provider: provider,
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot(),
            options: WidgetUsageOptions(intent: configuration))
    }

    func timeline(
        for configuration: ProviderSelectionIntent,
        in context: Context) async -> Timeline<SharinganWidgetEntry>
    {
        let provider = configuration.provider.provider
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot()
        let now = Date()
        let entry = SharinganWidgetEntry(
            date: now,
            provider: provider,
            snapshot: snapshot,
            options: WidgetUsageOptions(intent: configuration))
        let refresh = BurnDownRefreshSchedule.nextRefresh(snapshot: snapshot, provider: provider, now: now)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

struct SharinganSwitcherTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SharinganSwitcherEntry {
        let snapshot = WidgetPreviewData.snapshot()
        let providers = Self.supportedProviders(from: snapshot)
        return SharinganSwitcherEntry(
            date: Date(),
            provider: providers.first ?? .codex,
            availableProviders: providers,
            snapshot: snapshot)
    }

    func snapshot(for configuration: SwitcherSelectionIntent, in context: Context) async -> SharinganSwitcherEntry {
        self.makeEntry(include: configuration.include, order: configuration.order)
    }

    func timeline(
        for configuration: SwitcherSelectionIntent,
        in context: Context) async -> Timeline<SharinganSwitcherEntry>
    {
        let entry = self.makeEntry(include: configuration.include, order: configuration.order)
        let refresh = BurnDownRefreshSchedule.nextRefresh(
            snapshot: entry.snapshot,
            provider: entry.provider,
            now: entry.date)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry(
        include: WidgetSwitcherIncludeChoice,
        order: WidgetSwitcherOrderChoice) -> SharinganSwitcherEntry
    {
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot()
        let providers = Self.supportedProviders(from: snapshot, include: include, order: order)
        let stored = WidgetSelectionStore.loadSelectedProvider()
        let selected = providers.first { $0.instanceID == stored } ?? providers.first ?? .codex
        // Every Switcher shares the stored selection. Only a default Switcher repairs it, and only when no
        // Switcher can show the stored provider, so neither kind undoes a pick made in the other.
        if selected.instanceID != stored,
           WidgetSwitcherProviders.repairsStoredSelection(stored, include: include, in: snapshot)
        {
            WidgetSelectionStore.saveSelectedProvider(selected)
        }
        return SharinganSwitcherEntry(
            date: Date(),
            provider: selected,
            availableProviders: providers,
            snapshot: snapshot)
    }

    static func supportedProviders(from snapshot: WidgetSnapshot) -> [UsageProvider] {
        let enabled = snapshot.enabledProviders
        let instanceIDs = enabled.isEmpty ? snapshot.entries.map(\.provider) : enabled
        let supported = instanceIDs.compactMap { instanceID -> UsageProvider? in
            guard let provider = instanceID.firstPartyProvider, ProviderChoice(provider: provider) != nil else {
                return nil
            }
            return provider
        }
        return supported.isEmpty ? [.codex] : supported
    }

    /// Applies a Switcher's configured membership and order; the defaults return the list above unchanged.
    static func supportedProviders(
        from snapshot: WidgetSnapshot,
        include: WidgetSwitcherIncludeChoice,
        order: WidgetSwitcherOrderChoice) -> [UsageProvider]
    {
        let included: [UsageProvider] = switch include {
        case .automatic: self.supportedProviders(from: snapshot)
        case .all: WidgetSwitcherProviders.allProviders(in: snapshot)
        }
        let providers = included.isEmpty ? self.supportedProviders(from: snapshot) : included
        return WidgetSwitcherProviders.ordered(providers, in: snapshot, by: order)
    }
}

struct SharinganCompactTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SharinganCompactEntry {
        SharinganCompactEntry(
            date: Date(),
            provider: .codex,
            metric: .credits,
            snapshot: WidgetPreviewData.snapshot())
    }

    func snapshot(for configuration: CompactMetricSelectionIntent, in context: Context) async -> SharinganCompactEntry {
        let provider = configuration.provider.provider
        let metric = configuration.metric
        return SharinganCompactEntry(
            date: Date(),
            provider: provider,
            metric: metric,
            snapshot: WidgetSnapshotStore.load() ?? WidgetPreviewData.snapshot())
    }

    func timeline(
        for configuration: CompactMetricSelectionIntent,
        in context: Context) async -> Timeline<SharinganCompactEntry>
    {
        let provider = configuration.provider.provider
        let metric = configuration.metric
        let snapshot = WidgetSnapshotStore.load() ?? WidgetPreviewData.emptySnapshot()
        let entry = SharinganCompactEntry(
            date: Date(),
            provider: provider,
            metric: metric,
            snapshot: snapshot)
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

enum WidgetPreviewData {
    static func emptySnapshot() -> WidgetSnapshot {
        WidgetSnapshot(entries: [], enabledProviders: [], generatedAt: Date())
    }

    static func snapshot() -> WidgetSnapshot {
        let now = Date()
        let primary = RateWindow(
            usedPercent: 35,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(4 * 3600),
            resetDescription: "Resets in 4h")
        let secondary = RateWindow(
            usedPercent: 60,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(3 * 86400),
            resetDescription: "Resets in 3d")
        let entry = WidgetSnapshot.ProviderEntry(
            provider: .codex,
            updatedAt: now,
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            creditsRemaining: 1243.4,
            codeReviewRemainingPercent: 78,
            tokenUsage: WidgetSnapshot.TokenUsageSummary(
                sessionCostUSD: 12.4,
                sessionTokens: 420_000,
                last30DaysCostUSD: 923.8,
                last30DaysTokens: 12_400_000),
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-01", totalTokens: 120_000, costUSD: 15.2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-02", totalTokens: 80000, costUSD: 10.1),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-03", totalTokens: 140_000, costUSD: 17.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-04", totalTokens: 90000, costUSD: 11.4),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-05", totalTokens: 160_000, costUSD: 19.8),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-06", totalTokens: 70000, costUSD: 8.9),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2025-12-07", totalTokens: 110_000, costUSD: 13.7),
            ])
        return WidgetSnapshot(entries: [entry], generatedAt: now)
    }
}
