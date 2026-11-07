import CodexBarCore
import Foundation
import Testing
@testable import CodexBarWidget

struct WidgetConfigurationOptionsTests {
    /// The raw values saved widgets stored before the provider catalog was widened.
    private static let legacyProviderRawValues = [
        "codex", "claude", "gemini", "alibaba", "alibabatokenplan", "qwencloud", "antigravity", "cursor", "zai",
        "copilot", "devin", "minimax", "kilo", "opencode", "opencodego", "mistral", "kimi", "deepseek",
        "openrouter", "pi",
    ]

    private static let now = Date(timeIntervalSince1970: 1_793_880_000) // 2026-11-05 12:00 UTC

    // MARK: - Provider catalog and options

    @Test
    func `provider catalog covers every built in provider with registry titles`() throws {
        #expect(Set(ProviderChoice.allCases.map(\.rawValue)) == Set(UsageProvider.allCases.map(\.rawValue)))
        for choice in ProviderChoice.allCases {
            let display = try #require(ProviderChoice.caseDisplayRepresentations[choice])
            #expect(String(localized: display.title)
                == ProviderDescriptorRegistry.descriptor(for: choice.provider).metadata.displayName)
        }
    }

    @Test
    func `legacy configured provider values still resolve to the same provider`() throws {
        let stored = Data(#"[{"provider":"claude"},{"provider":"kimi"},{"provider":"pi"}]"#.utf8)
        let decoded = try JSONDecoder().decode([[String: String]].self, from: stored).compactMap { $0["provider"] }
        for raw in Self.legacyProviderRawValues + decoded {
            let choice = try #require(ProviderChoice(rawValue: raw))
            #expect(choice.provider.rawValue == raw)
            // Still in the original set, so the default Switcher list is unchanged.
            #expect(ProviderChoice(provider: choice.provider) == choice)
            let intent = ProviderSelectionIntent()
            intent.provider = choice
            #expect(intent.provider.provider.rawValue == raw)
            #expect(WidgetUsageOptions(intent: intent) == WidgetUsageOptions())
        }
    }

    @Test
    func `provider options list providers with data sorted by display name`() {
        let snapshot = WidgetSnapshot(
            entries: [
                Self.entry(provider: .zai),
                Self.entry(provider: .kiro),
                Self.entry(provider: .claude),
                Self.entry(provider: .codex),
            ],
            enabledProviders: [.zai, .kiro, .claude, .gemini],
            generatedAt: Self.now)

        // Codex has data but is disabled; Gemini is enabled but has no data yet.
        #expect(WidgetProviderOptions.choices(in: snapshot) == [.claude, .kiro, .zai])
        #expect(ProviderChoice(provider: .kiro) == nil)
        #expect(ProviderChoice(catalogProvider: .kiro) == .kiro)
    }

    @Test
    func `provider options fall back to the original picker set before any data`() {
        let legacy = UsageProvider.allCases.filter { ProviderChoice(provider: $0) != nil }
        let expected = WidgetProviderNames.sorted(legacy).compactMap { ProviderChoice(catalogProvider: $0) }
        #expect(expected.count == Self.legacyProviderRawValues.count)
        #expect(WidgetProviderOptions.choices(in: nil) == expected)
        #expect(WidgetProviderOptions.choices(in: WidgetPreviewData.emptySnapshot()) == expected)
    }

    // MARK: - Defaults

    @Test
    func `option defaults reproduce the unconfigured widgets`() {
        let intent = ProviderSelectionIntent()
        #expect(intent.provider == .codex)
        #expect(intent.metric == .automatic)
        #expect(intent.window == .automatic)
        #expect(intent.range == .automatic)
        #expect(WidgetUsageOptions(intent: intent) == WidgetUsageOptions())
        #expect(CodexBarWidgetEntry(date: Self.now, provider: .codex, snapshot: WidgetPreviewData.emptySnapshot())
            .options == WidgetUsageOptions())

        let switcher = SwitcherSelectionIntent()
        #expect(switcher.include == .automatic)
        #expect(switcher.order == .automatic)

        for showsUsed in [false, true] {
            let snapshot = WidgetSnapshot(entries: [], usageBarsShowUsed: showsUsed, generatedAt: Self.now)
            #expect(WidgetUsageOptions().showsUsed(in: snapshot) == showsUsed)
        }

        let entry = Self.windowedEntry()
        let lanes = WidgetTileLane.lanes(for: entry)
        #expect(WidgetHeadlineWindow.apply(.automatic, to: lanes, entry: entry) == lanes)

        let history = WidgetHistoryRange.series(for: Self.historyEntry(), range: .automatic, now: Self.now)
        #expect(history.points.map(\.dayKey) == Self.historyEntry().dailyUsage.map(\.dayKey))
        #expect(history.dayCount == nil)
        #expect(WidgetHistoryRange.barSpacing(pointCount: 90, isRanged: false) == 3)
    }

    @Test
    func `default switcher options keep the original list and order`() {
        let snapshot = WidgetSnapshot(
            entries: [Self.entry(provider: .codex, used: 50), Self.entry(provider: .claude, used: 90)],
            enabledProviders: [.codex, .kiro, .claude],
            generatedAt: Self.now)
        let original = CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot)
        #expect(original == [.codex, .claude])
        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(
            from: snapshot, include: .automatic, order: .automatic) == original)
    }

    // MARK: - Metric

    @Test
    func `metric option overrides the app preference only when chosen`() {
        for appSetting in [false, true] {
            #expect(WidgetUsageMetricChoice.automatic.showsUsed(appSetting: appSetting) == appSetting)
            #expect(!WidgetUsageMetricChoice.remaining.showsUsed(appSetting: appSetting))
            #expect(WidgetUsageMetricChoice.used.showsUsed(appSetting: appSetting))
        }
    }

    // MARK: - Window

    @Test
    func `window option headlines the chosen window`() {
        let entry = Self.windowedEntry()
        let expected: [(WidgetUsageWindowChoice, String)] = [
            (.automatic, "secondary"),
            (.session, "primary"),
            (.weekly, "secondary"),
            (.monthly, "tertiary"),
        ]
        for (window, laneID) in expected {
            let lanes = WidgetHeadlineWindow.apply(window, to: WidgetTileLane.lanes(for: entry), entry: entry)
            #expect(WidgetTilePlan.make(lanes: lanes, maxSecondaryLanes: 2).hero?.id == laneID)
        }
    }

    @Test
    func `window option falls back to the binding lane when the provider lacks that window`() {
        let entry = Self.windowedEntry(includesMonthly: false)
        let lanes = WidgetHeadlineWindow.apply(.monthly, to: WidgetTileLane.lanes(for: entry), entry: entry)
        #expect(lanes == WidgetTileLane.lanes(for: entry))
        #expect(WidgetTilePlan.make(lanes: lanes, maxSecondaryLanes: 2).hero?.id == "secondary")
    }

    @Test
    func `window option keeps the provider's binding lane over a model-scoped lane of the same window`() {
        // Claude binds the overall weekly lane; its tertiary lane is the model-scoped weekly lane.
        let entry = Self.windowedEntry(provider: .claude, tertiaryUsed: 95, tertiaryMinutes: 10080)
        let lanes = WidgetHeadlineWindow.apply(.weekly, to: WidgetTileLane.lanes(for: entry), entry: entry)
        #expect(WidgetTilePlan.make(lanes: lanes, maxSecondaryLanes: 2).hero?.id == "secondary")
        #expect(lanes.first { $0.id == "tertiary" }?.isHeadlineCandidate == false)
    }

    @Test
    func `lane windows come from durations or from lane IDs without durations`() {
        let entry = Self.windowedEntry()
        #expect(WidgetHeadlineWindow.cadence(of: "primary", entry: entry) == .session)
        #expect(WidgetHeadlineWindow.cadence(of: "secondary", entry: entry) == .weekly)
        #expect(WidgetHeadlineWindow.cadence(of: "tertiary", entry: entry) == .monthly)
        let bare = Self.entry(provider: .gemini)
        #expect(WidgetHeadlineWindow.cadence(of: "session", entry: bare) == .session)
        #expect(WidgetHeadlineWindow.cadence(of: "fixture-weekly", entry: bare) == .weekly)
        #expect(WidgetHeadlineWindow.cadence(of: "fixture-monthly", entry: bare) == .monthly)
        #expect(WidgetHeadlineWindow.cadence(of: "fixture-total", entry: bare) == nil)
    }

    // MARK: - History range

    @Test
    func `history range zero fills the chosen days up to today`() {
        let series = WidgetHistoryRange.series(
            for: Self.historyEntry(coverageDays: 30),
            range: .last7Days,
            now: Self.now,
            timeZone: Self.utc)
        #expect(series.points.map(\.dayKey) == [
            "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05",
        ])
        #expect(series.points.map(\.costUSD) == [0, 0, 2, 0, 4, 0, 0])
        #expect(series.dayCount == 7)
        #expect(UsageHistoryChartMode.isCostMode(series.points))
    }

    @Test
    func `history range covers ninety days when the app keeps them`() {
        let series = WidgetHistoryRange.series(
            for: Self.historyEntry(coverageDays: 90),
            range: .last90Days,
            now: Self.now,
            timeZone: Self.utc)
        #expect(series.points.count == 90)
        #expect(series.points.first?.dayKey == "2026-08-08")
        #expect(series.points.last?.dayKey == "2026-11-05")
        #expect(series.dayCount == 90)
        #expect(WidgetHistoryRange.barSpacing(pointCount: series.points.count, isRanged: true) == 1)
        #expect(WidgetHistoryRange.barSpacing(pointCount: 7, isRanged: true) == 3)
    }

    @Test
    func `history range never invents days before the history the app covers`() {
        for coverage in [nil, 3] as [Int?] {
            let series = WidgetHistoryRange.series(
                for: Self.historyEntry(coverageDays: coverage),
                range: .last90Days,
                now: Self.now,
                timeZone: Self.utc)
            // Starts at the earliest recorded day, never ninety days back.
            #expect(series.points.first?.dayKey == "2026-11-01")
            #expect(series.dayCount == 5)
        }
    }

    @Test
    func `history range keeps token mode and skips empty history`() {
        let tokens = WidgetSnapshot.ProviderEntry(
            provider: .gemini,
            updatedAt: Self.now,
            primary: nil,
            secondary: nil,
            dailyUsage: [WidgetSnapshot.DailyUsagePoint(dayKey: "2026-11-04", totalTokens: 1200, costUSD: nil)],
            dailyUsageHistoryDays: 30)
        let series = WidgetHistoryRange.series(for: tokens, range: .last7Days, now: Self.now, timeZone: Self.utc)
        #expect(series.points.count == 7)
        #expect(series.points.allSatisfy { $0.costUSD == nil })
        #expect(!UsageHistoryChartMode.isCostMode(series.points))

        let empty = WidgetHistoryRange.series(
            for: Self.entry(provider: .gemini),
            range: .last30Days,
            now: Self.now,
            timeZone: Self.utc)
        #expect(empty.points.isEmpty)
        #expect(empty.dayCount == nil)
    }

    // MARK: - Snapshot compatibility

    @Test
    func `snapshot entries round trip the history coverage`() throws {
        let snapshot = WidgetSnapshot(entries: [Self.historyEntry(coverageDays: 90)], generatedAt: Self.now)
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let entries = object?["entries"] as? [[String: Any]]
        #expect(entries?.first?["dailyUsageHistoryDays"] as? Int == 90)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: encoded)
        #expect(decoded.entries.first?.dailyUsageHistoryDays == 90)
    }

    @Test
    func `snapshots without history coverage still decode`() throws {
        let snapshot = WidgetSnapshot(entries: [Self.historyEntry(coverageDays: nil)], generatedAt: Self.now)
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let entries = object?["entries"] as? [[String: Any]]
        #expect(entries?.first?["dailyUsageHistoryDays"] == nil)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: encoded)
        #expect(decoded.entries.first?.dailyUsageHistoryDays == nil)
        #expect(decoded.entries.first?.dailyUsage.count == 2)
    }

    // MARK: - Switcher

    @Test
    func `switcher can include every provider and sort by name or usage`() {
        let snapshot = WidgetSnapshot(
            entries: [Self.entry(provider: .codex, used: 50), Self.entry(provider: .claude, used: 90)],
            enabledProviders: [.codex, .kiro, .claude],
            generatedAt: Self.now)
        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(
            from: snapshot, include: .all, order: .automatic) == [.codex, .kiro, .claude])
        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(
            from: snapshot, include: .all, order: .name) == [.claude, .codex, .kiro])
        // Least quota left first; a provider with no quota follows.
        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(
            from: snapshot, include: .all, order: .usage) == [.claude, .codex, .kiro])
        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(
            from: snapshot, include: .automatic, order: .usage) == [.claude, .codex])
    }

    @Test
    func `a default switcher keeps a provider picked in an all providers switcher`() {
        let snapshot = WidgetSnapshot(
            entries: [Self.entry(provider: .codex, used: 50), Self.entry(provider: .kiro, used: 20)],
            enabledProviders: [.codex, .kiro, .claude],
            generatedAt: Self.now)
        // Kiro is outside the default set, so only an All providers Switcher can have stored it.
        #expect(!CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot).contains(.kiro))
        #expect(!WidgetSwitcherProviders.repairsStoredSelection(.kiro, include: .automatic, in: snapshot))
        #expect(!WidgetSwitcherProviders.repairsStoredSelection(.codex, include: .automatic, in: snapshot))
        // A stored provider no Switcher can show, or none at all, is still repaired, by the default Switcher only.
        #expect(WidgetSwitcherProviders.repairsStoredSelection(.gemini, include: .automatic, in: snapshot))
        #expect(WidgetSwitcherProviders.repairsStoredSelection(nil, include: .automatic, in: snapshot))
        #expect(!WidgetSwitcherProviders.repairsStoredSelection(.gemini, include: .all, in: snapshot))
        #expect(!WidgetSwitcherProviders.repairsStoredSelection(nil, include: .all, in: snapshot))
        // Before the app publishes anything, the default Switcher repairs a stale selection as it always did.
        let empty = WidgetPreviewData.emptySnapshot()
        #expect(WidgetSwitcherProviders.repairsStoredSelection(.claude, include: .automatic, in: empty))
    }

    @Test
    func `switcher with every provider falls back to the original list when nothing is enabled`() {
        let snapshot = WidgetPreviewData.emptySnapshot()
        #expect(CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot, include: .all, order: .name)
            == CodexBarSwitcherTimelineProvider.supportedProviders(from: snapshot))
    }

    // MARK: - Fixtures

    private static let utc = TimeZone(secondsFromGMT: 0) ?? .current

    private static func entry(provider: UsageProvider, used: Double? = nil) -> WidgetSnapshot.ProviderEntry {
        WidgetSnapshot.ProviderEntry(
            provider: provider,
            updatedAt: self.now,
            primary: used.map { RateWindow(usedPercent: $0, windowMinutes: 300, resetsAt: nil, resetDescription: nil) },
            secondary: nil)
    }

    private static func windowedEntry(
        provider: UsageProvider = .gemini,
        includesMonthly: Bool = true,
        tertiaryUsed: Double = 50,
        tertiaryMinutes: Int = 43200) -> WidgetSnapshot.ProviderEntry
    {
        func row(_ id: String, used: Double, minutes: Int) -> WidgetSnapshot.WidgetUsageRowSnapshot {
            WidgetSnapshot.WidgetUsageRowSnapshot(
                id: id,
                title: id,
                percentLeft: 100 - used,
                window: RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: nil, resetDescription: nil))
        }
        var rows = [row("primary", used: 20, minutes: 300), row("secondary", used: 90, minutes: 10080)]
        if includesMonthly {
            rows.append(row("tertiary", used: tertiaryUsed, minutes: tertiaryMinutes))
        }
        return WidgetSnapshot.ProviderEntry(
            provider: provider,
            updatedAt: self.now,
            primary: nil,
            secondary: nil,
            usageRows: rows)
    }

    private static func historyEntry(coverageDays: Int? = 30) -> WidgetSnapshot.ProviderEntry {
        WidgetSnapshot.ProviderEntry(
            provider: .gemini,
            updatedAt: self.now,
            primary: nil,
            secondary: nil,
            dailyUsage: [
                WidgetSnapshot.DailyUsagePoint(dayKey: "2026-11-01", totalTokens: 100, costUSD: 2),
                WidgetSnapshot.DailyUsagePoint(dayKey: "2026-11-03", totalTokens: 300, costUSD: 4),
            ],
            dailyUsageHistoryDays: coverageDays)
    }
}
