import SharinganCore
import SwiftUI

struct SpendActivityPalette {
    let colorScheme: ColorScheme
    var contrast: ColorSchemeContrast = .standard
    /// Accents and colorblind-safe keep the green ramp, a single-hue ramp read by lightness alone;
    /// monochrome swaps in grays at the same lightness steps.
    var mode: ChartPaletteMode = ChartPaletteSetting.activeMode

    func color(forLevel level: Int) -> Color {
        Self.rgb(self.levelHexes[min(max(level, 0), 4)])
    }

    /// The five level colors, empty cell first.
    var levelHexes: [UInt32] {
        if self.mode == .monochrome {
            return self.monochromeLevelHexes
        }
        return switch (self.colorScheme, self.contrast) {
        case (.dark, .increased): [0x484C52, 0x469960, 0x58B872, 0x7DDF96, 0xADF0BC]
        case (.dark, _): [0x30353A, 0x347D4E, 0x43985D, 0x58B872, 0x7DDF96]
        case (_, .increased): [0xE1E5E9, 0x519C66, 0x34804C, 0x24693B, 0x17552E]
        default: [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
        }
    }

    /// Neutral grays about 12–15 L* apart, keeping each empty-cell color so "no activity" reads the same.
    /// Dark levels keep 3:1 against the dark window background, like the green ramp.
    private var monochromeLevelHexes: [UInt32] {
        switch (self.colorScheme, self.contrast) {
        case (.dark, .increased): [0x484C52, 0x868686, 0xA6A6A6, 0xC6C6C6, 0xE8E8E8]
        case (.dark, _): [0x30353A, 0x707070, 0x8E8E8E, 0xADADAD, 0xD6D6D6]
        case (_, .increased): [0xE1E5E9, 0x969696, 0x777777, 0x5C5C5C, 0x424242]
        default: [0xEBEDF0, 0xC6C6C6, 0xA0A0A0, 0x7C7C7C, 0x555555]
        }
    }

    var unavailableFill: Color {
        Self.rgb(self.colorScheme == .dark ? 0x282D34 : 0xE1E6EC)
    }

    var unavailableStroke: Color {
        Self.rgb(self.colorScheme == .dark ? 0x8A959F : 0x6D7888)
    }

    /// The same shape marks missing history in the legend and both activity grids.
    /// A slash preserves the distinction from a confirmed zero without relying on hue.
    func drawCell(in context: inout GraphicsContext, rect: CGRect, corner: CGFloat, level: Int?) {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let path = shape.path(in: rect)
        context.fill(path, with: .color(level.map { self.color(forLevel: $0) } ?? self.unavailableFill))
        guard level == nil else { return }
        context.stroke(
            shape.path(in: rect.insetBy(dx: 0.5, dy: 0.5)),
            with: .color(self.unavailableStroke),
            lineWidth: 0.75)
        let inset = min(rect.width * 0.25, 2)
        var slash = Path()
        slash.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        slash.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        context.stroke(slash, with: .color(self.unavailableStroke), lineWidth: 0.75)
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct SpendActivitySwatch: View {
    let palette: SpendActivityPalette
    var level: Int?

    var body: some View {
        Canvas { context, size in
            self.palette.drawCell(in: &context, rect: CGRect(origin: .zero, size: size), corner: 2, level: self.level)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}
