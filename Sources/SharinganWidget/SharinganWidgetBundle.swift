import SwiftUI
import WidgetKit

@main
struct SharinganWidgetBundle: WidgetBundle {
    var body: some Widget {
        SharinganSwitcherWidget()
        SharinganUsageWidget()
        SharinganHistoryWidget()
        SharinganCompactWidget()
        SharinganBurnDownWidget()
        SharinganCombinedBurnDownWidget()
        SharinganAccountUsageWidget()
        SharinganAccountsWidget()
    }
}

struct SharinganSwitcherWidget: Widget {
    private let kind = "SharinganSwitcherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: self.kind,
            provider: SharinganSwitcherTimelineProvider())
        { entry in
            SharinganSwitcherWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("Sharingan Switcher")))
        .description(Text(W("Usage widget with a provider switcher.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SharinganUsageWidget: Widget {
    private let kind = "SharinganUsageWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: SharinganTimelineProvider())
        { entry in
            SharinganUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("Sharingan Usage")))
        .description(Text(W("Session and weekly usage with credits and costs.")))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SharinganHistoryWidget: Widget {
    private let kind = "SharinganHistoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: ProviderSelectionIntent.self,
            provider: SharinganTimelineProvider())
        { entry in
            SharinganHistoryWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("Sharingan History")))
        .description(Text(W("Usage history chart with recent totals.")))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SharinganCompactWidget: Widget {
    private let kind = "SharinganCompactWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: CompactMetricSelectionIntent.self,
            provider: SharinganCompactTimelineProvider())
        { entry in
            SharinganCompactWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("Sharingan Metric")))
        .description(Text(W("Compact widget for credits or cost.")))
        .supportedFamilies([.systemSmall])
    }
}

enum BurnDownWidgetBackgroundConfiguration {
    static let isRemovable = true
}

struct SharinganBurnDownWidget: Widget {
    private let kind = "SharinganBurnDownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: BurnDownSelectionIntent.self,
            provider: BurnDownTimelineProvider())
        { entry in
            BurnDownWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("Sharingan Burn Down")))
        .description(Text(W("Remaining budget compared with an ideal steady burn rate.")))
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(BurnDownWidgetBackgroundConfiguration.isRemovable)
    }
}

struct SharinganCombinedBurnDownWidget: Widget {
    private let kind = "SharinganCombinedBurnDownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: self.kind,
            intent: BurnProviderSelectionIntent.self,
            provider: CombinedBurnDownTimelineProvider())
        { entry in
            CombinedBurnDownWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(W("Sharingan Burn Down (Combined)")))
        .description(Text(W("Two quota burn-down charts in one tile.")))
        .supportedFamilies([.systemMedium])
        .containerBackgroundRemovable(BurnDownWidgetBackgroundConfiguration.isRemovable)
    }
}
