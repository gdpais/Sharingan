import SharinganCore
import SwiftUI

/// "Card layout" in a provider's settings: section order and visibility, the card's chart, and menu links.
///
/// Rows move with up/down buttons, which work in grouped forms on every supported macOS, rather than drag and
/// drop. Every kind stays listed; one the provider is not reporting right now is marked unavailable, so a
/// choice made earlier can still be changed.
@MainActor
struct ProviderCardLayoutSettingsView: View {
    let provider: UsageProvider
    @Bindable var store: UsageStore

    var body: some View {
        let settings = self.store.settings
        let layout = settings.menuCardLayout(for: self.provider)
        let availability = self.store.menuCardLayoutAvailability(for: self.provider)
        let metadata = self.store.metadata(for: self.provider)
        let movable = layout.reorderableSections
        Section {
            ForEach(Array(movable.enumerated()), id: \.element.kind) { index, section in
                HStack(spacing: 8) {
                    self.visibilityToggle(section.kind, layout: layout, availability: availability)
                    Spacer(minLength: 8)
                    Button {
                        self.update { _ = $0.move(section.kind, by: -1) }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .help(L("Move up"))
                    .accessibilityLabel(L("Move up"))
                    .disabled(index == 0)
                    Button {
                        self.update { _ = $0.move(section.kind, by: 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .help(L("Move down"))
                    .accessibilityLabel(L("Move down"))
                    .disabled(index == movable.count - 1)
                }
            }
            self.visibilityToggle(.pace, layout: layout, availability: availability)

            SettingsMenuPicker(
                selection: Binding(
                    get: { settings.menuCardLayout(for: self.provider).chart },
                    set: { chart in self.update { $0.chart = chart } }),
                options: MenuCardChartChoice.allCases,
                label: { Text(L("Chart")) },
                optionLabel: { choice in
                    Text(Self.chartTitle(choice, availability: availability))
                })

            if metadata.dashboardURL != nil || metadata.statusPageURL != nil || metadata.statusLinkURL != nil {
                Text(L("Menu links"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if metadata.dashboardURL != nil {
                    self.menuLinkToggle(.usageDashboard, title: L("Usage Dashboard"), layout: layout)
                }
                if metadata.statusPageURL != nil || metadata.statusLinkURL != nil {
                    self.menuLinkToggle(.statusPage, title: L("Status Page"), layout: layout)
                }
            }

            Button(L("Restore Defaults")) {
                settings.resetMenuCardLayout(for: self.provider)
            }
            .disabled(layout.isDefault)
        } header: {
            Text(L("Card layout"))
        } footer: {
            SettingsSectionFooter(L(
                // swiftlint:disable:next line_length
                "Order and show this provider's menu card sections, and pick its chart. Sections and charts without data stay hidden."))
        }
    }

    private func visibilityToggle(
        _ kind: MenuCardSectionKind,
        layout: MenuCardLayout,
        availability: MenuCardLayoutAvailability) -> some View
    {
        Toggle(
            isOn: Binding(
                get: { layout.isVisible(kind) },
                set: { isVisible in self.update { $0.setVisible(isVisible, for: kind) } }))
        {
            VStack(alignment: .leading) {
                Text(Self.sectionTitle(kind, availability: availability))
                if kind == .pace {
                    Text(L("Drawn inside usage rows."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private func menuLinkToggle(_ item: MenuCardMenuItem, title: String, layout: MenuCardLayout) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { layout.showsMenuItem(item) },
                set: { visible in self.update { $0.setMenuItem(item, visible: visible) } }))
            .toggleStyle(.checkbox)
    }

    private func update(_ mutate: (inout MenuCardLayout) -> Void) {
        self.store.settings.updateMenuCardLayout(for: self.provider, mutate)
    }

    // MARK: - Titles

    static func sectionTitle(_ kind: MenuCardSectionKind, availability: MenuCardLayoutAvailability) -> String {
        let title = switch kind {
        case .usage: L("Usage rows")
        case .pace: L("display_mode_pace")
        case .chart: L("Chart")
        case .credits: L("Credits")
        case .extraUsage: L("Extra usage")
        case .cost: L("Cost")
        }
        return availability.sections.contains(kind) ? title : L("%@ (unavailable)", title)
    }

    static func chartTitle(_ choice: MenuCardChartChoice, availability: MenuCardLayoutAvailability) -> String {
        let title = switch choice {
        case .automatic: L("Automatic")
        case .live: L("Live")
        case .spend: L("Spend")
        case .burndown: L("Burn Down")
        case .planFit: L("Plan fit")
        case .none: L("None")
        }
        let needsData = MenuCardChartChoice.dataCharts.contains(choice)
        return !needsData || availability.charts.contains(choice) ? title : L("%@ (unavailable)", title)
    }
}
