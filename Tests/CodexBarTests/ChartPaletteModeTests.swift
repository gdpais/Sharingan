import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

struct ChartPaletteModeTests {
    private static let slots: [ChartPalette.Slot] = (0..<ChartPalette.slotCount).map { .index($0) } + [.other]

    // MARK: - Series colors

    @Test
    func `provider accents keep today's colors`() {
        for slot in Self.slots {
            #expect(ChartPalette.color(for: slot, mode: .accents) == ChartPalette.color(for: slot))
        }
        #expect(ChartPalette.otherColor(mode: .accents) == ChartPalette.otherColor)
        #expect(ChartPalette.singleSeriesColor(accent: .pink, mode: .accents) == .pink)
        for series in [CostHistoryModelStack.Series.model(0), .model(1), .other] {
            #expect(CostHistoryStackPresentation.color(for: series, mode: .accents)
                == CostHistoryStackPresentation.color(for: series))
        }
    }

    @Test
    func `colorblind-safe paints single series with the first validated slot`() {
        #expect(ChartPalette.singleSeriesColor(accent: .pink, mode: .colorblindSafe)
            == ChartPalette.color(for: .index(0)))
        #expect(ChartPalette.swatch(for: .index(0), mode: .colorblindSafe) == ChartPalette.Swatch(
            light: 0x2A78D6,
            dark: 0x3987E5))
        for (index, swatch) in ChartPalette.swatches.enumerated() {
            #expect(ChartPalette.swatch(for: .index(index), mode: .colorblindSafe) == swatch)
            let validated = ChartPalette.color(for: .index(index))
            #expect(ChartPalette.color(for: .index(index), mode: .colorblindSafe) == validated)
        }
        #expect(ChartPalette.swatch(for: .other, mode: .colorblindSafe) == ChartPalette.otherSwatch)
    }

    @Test
    func `monochrome grays keep their contrast in light and dark`() {
        let series = ChartPalette.monochromeSwatches
        for swatch in series + [ChartPalette.monochromeOtherSwatch] {
            #expect(Self.isGray(swatch.light) && Self.isGray(swatch.dark))
        }
        for swatch in series {
            #expect(Self.contrast(swatch.light, 0xFFFFFF) >= 4.5)
            #expect(Self.contrast(swatch.light, 0xECECEC) >= 4.5)
            #expect(Self.contrast(swatch.dark, 0x1E1E1E) >= 4.5)
            #expect(Self.contrast(swatch.dark, 0x2B2B2B) >= 4.5)
        }
        #expect(Self.contrast(ChartPalette.monochromeOtherSwatch.light, 0xFFFFFF) >= 3)
        #expect(Self.contrast(ChartPalette.monochromeOtherSwatch.dark, 0x1E1E1E) >= 3)

        // Each gray, "Other" last, stays visibly apart from the one stacked next to it.
        let ramp = series + [ChartPalette.monochromeOtherSwatch]
        for index in 1..<ramp.count {
            #expect(Self.lightness(ramp[index].light) - Self.lightness(ramp[index - 1].light) >= 10)
            #expect(Self.lightness(ramp[index - 1].dark) - Self.lightness(ramp[index].dark) >= 10)
        }
    }

    @Test
    func `monochrome slots past the grays share the last one`() {
        let last = ChartPalette.monochromeSwatches[ChartPalette.monochromeSwatches.count - 1]
        #expect(ChartPalette.swatch(for: .index(0), mode: .monochrome) == ChartPalette.monochromeSwatches[0])
        #expect(ChartPalette.swatch(for: .index(7), mode: .monochrome) == last)
        #expect(ChartPalette.swatch(for: .other, mode: .monochrome) == ChartPalette.monochromeOtherSwatch)
        #expect(ChartPalette.singleSeriesColor(accent: .pink, mode: .monochrome)
            == ChartPalette.color(for: .index(0), mode: .monochrome))
    }

    // MARK: - Heatmap ramp

    @Test(arguments: [ColorScheme.light, .dark])
    func `heatmap keeps the green ramp unless monochrome`(scheme: ColorScheme) {
        for contrast in [ColorSchemeContrast.standard, .increased] {
            let accents = SpendActivityPalette(colorScheme: scheme, contrast: contrast, mode: .accents)
            let colorblind = SpendActivityPalette(colorScheme: scheme, contrast: contrast, mode: .colorblindSafe)
            #expect(accents.levelHexes == Self.greenRamp(scheme: scheme, contrast: contrast))
            #expect(colorblind.levelHexes == accents.levelHexes)
            // The default palette is today's ramp.
            #expect(SpendActivityPalette(colorScheme: scheme, contrast: contrast).levelHexes == accents.levelHexes)
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `monochrome heatmap is a gray lightness ramp`(scheme: ColorScheme) {
        for contrast in [ColorSchemeContrast.standard, .increased] {
            let gray = SpendActivityPalette(colorScheme: scheme, contrast: contrast, mode: .monochrome).levelHexes
            let green = Self.greenRamp(scheme: scheme, contrast: contrast)
            #expect(gray.count == 5)
            #expect(gray[0] == green[0])
            #expect(gray.dropFirst().allSatisfy(Self.isGray))
            for level in 1..<gray.count {
                let step = Self.lightness(gray[level]) - Self.lightness(gray[level - 1])
                // Activity darkens in light mode and brightens in dark mode, as with the green ramp.
                #expect(scheme == .dark ? step >= 10 : step <= -10)
            }
            if scheme == .dark {
                for level in 1..<gray.count {
                    #expect(Self.contrast(gray[level], 0x232323) >= 3)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func greenRamp(scheme: ColorScheme, contrast: ColorSchemeContrast) -> [UInt32] {
        switch (scheme, contrast) {
        case (.dark, .increased): [0x484C52, 0x469960, 0x58B872, 0x7DDF96, 0xADF0BC]
        case (.dark, _): [0x30353A, 0x347D4E, 0x43985D, 0x58B872, 0x7DDF96]
        case (_, .increased): [0xE1E5E9, 0x519C66, 0x34804C, 0x24693B, 0x17552E]
        default: [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
        }
    }

    private static func isGray(_ hex: UInt32) -> Bool {
        let red = (hex >> 16) & 0xFF
        let green = (hex >> 8) & 0xFF
        let blue = hex & 0xFF
        return red == green && green == blue
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 0xFF) + 0.7152 * linear((hex >> 8) & 0xFF) + 0.0722 * linear(hex & 0xFF)
    }

    private static func contrast(_ lhs: UInt32, _ rhs: UInt32) -> Double {
        let lhs = self.relativeLuminance(lhs)
        let rhs = self.relativeLuminance(rhs)
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }

    /// CIELAB L*, the lightness the ramp steps are designed in.
    private static func lightness(_ hex: UInt32) -> Double {
        let luminance = self.relativeLuminance(hex)
        return luminance > 0.008856 ? 116 * cbrt(luminance) - 16 : 903.3 * luminance
    }
}
