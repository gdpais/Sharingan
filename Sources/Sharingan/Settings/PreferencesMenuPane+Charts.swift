import SharinganCore
import SwiftUI

/// "Charts" section of the Menu pane: range, stacking, average line, style and palette for the cost
/// history charts. The choices are stored outside the observed settings, so the section keeps its own
/// copy and writes every change through.
@MainActor
struct ChartPreferencesSettingsSection: View {
    let settings: SettingsStore
    @State private var preferences: ChartPreferences

    init(settings: SettingsStore) {
        self.settings = settings
        self._preferences = State(initialValue: settings.chartPreferences)
    }

    var body: some View {
        Section {
            SettingsMenuPicker(
                selection: self.$preferences.range,
                options: ChartPreferences.RangeOption.allCases,
                label: {
                    SettingsRowLabel(L("Range"), subtitle: L("Charts never show more days than the History window."))
                },
                optionLabel: { Text(Self.rangeLabel($0)) })

            Toggle(isOn: self.$preferences.stackByModel) {
                SettingsRowLabel(L("Stack by model"), subtitle: L("Splits each day by its two largest models."))
            }

            Toggle(isOn: self.$preferences.showsAverageLine) {
                Text(L("Average line"))
            }

            SettingsMenuPicker(
                selection: self.$preferences.style,
                options: ChartPreferences.Style.allCases,
                label: { Text(L("Chart style")) },
                optionLabel: { Text(Self.styleLabel($0)) })

            SettingsMenuPicker(
                selection: self.$preferences.paletteMode,
                options: ChartPaletteMode.allCases,
                label: {
                    SettingsRowLabel(
                        L("Palette"),
                        subtitle: L("Colorblind-safe replaces provider accents in single-series charts. "
                            + "Monochrome uses grays everywhere, heatmaps included."))
                },
                optionLabel: { Text(Self.paletteLabel($0)) })

            ChartPaletteSwatchRow(mode: self.preferences.paletteMode)
        } header: {
            Text(L("Charts"))
        }
        .onChange(of: self.preferences) { _, preferences in
            self.settings.setChartPreferences(preferences)
        }
    }

    nonisolated static func rangeLabel(_ range: ChartPreferences.RangeOption) -> String {
        guard let days = range.days else { return L("cost_history_window_title") }
        return String(format: L("Last %d days"), days)
    }

    nonisolated static func styleLabel(_ style: ChartPreferences.Style) -> String {
        switch style {
        case .bars: L("Bars")
        case .line: L("Line")
        }
    }

    nonisolated static func paletteLabel(_ mode: ChartPaletteMode) -> String {
        switch mode {
        case .accents: L("Provider accents")
        case .colorblindSafe: L("Colorblind-safe")
        case .monochrome: L("Monochrome")
        }
    }
}

/// A preview of a palette mode: single-series colors for the first providers, the series slots with
/// "Other", then the activity heatmap levels.
struct ChartPaletteSwatchRow: View {
    let mode: ChartPaletteMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.singleSeriesProviders.enumerated()), id: \.offset) { _, provider in
                self.swatch(ChartPalette.singleSeriesColor(accent: Self.accent(provider), mode: self.mode))
            }
            Spacer().frame(width: 8)
            ForEach(Self.previewSlots, id: \.self) { slot in
                self.swatch(ChartPalette.color(for: slot, mode: self.mode))
            }
            Spacer().frame(width: 8)
            let heatmap = SpendActivityPalette(colorScheme: self.colorScheme, contrast: self.contrast, mode: self.mode)
            ForEach(1..<5, id: \.self) { level in
                self.swatch(heatmap.color(forLevel: level))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    static let previewSlots: [ChartPalette.Slot] = [.index(0), .index(1), .index(2), .other]

    /// The first providers in registry order stand in for "a chart with one series".
    static var singleSeriesProviders: [UsageProvider] {
        Array(UsageProvider.allCases.prefix(2))
    }

    private static func accent(_ provider: UsageProvider) -> Color {
        let color = ProviderAccentPalette.color(for: provider)
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 14, height: 14)
    }
}
