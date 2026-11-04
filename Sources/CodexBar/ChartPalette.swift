import AppKit
import SwiftUI

/// Shared categorical palette for menu charts.
///
/// The order is validated for adjacent-hue contrast and common color-vision deficiencies, so slots
/// are handed out in order and never by hash: Swift seeds `String` hashing per process, which made
/// hash-picked colors change on every launch.
enum ChartPalette {
    enum Slot: Hashable, Sendable {
        /// Index into `ChartPalette.swatches`.
        case index(Int)
        /// Overflow past the last categorical slot; drawn in the neutral gray.
        case other
    }

    struct Swatch: Equatable, Sendable {
        let light: UInt32
        let dark: UInt32
    }

    // MARK: - Palette

    static let swatches: [Swatch] = [
        Swatch(light: 0x2A78D6, dark: 0x3987E5), // blue
        Swatch(light: 0xEB6834, dark: 0xD95926), // orange
        Swatch(light: 0x1BAF7A, dark: 0x199E70), // aqua
        Swatch(light: 0xEDA100, dark: 0xC98500), // yellow
        Swatch(light: 0xE87BA4, dark: 0xD55181), // magenta
        Swatch(light: 0x008300, dark: 0x008300), // green
        Swatch(light: 0x6250D6, dark: 0x9085E9), // violet
        Swatch(light: 0xE34948, dark: 0xE66767), // red
    ]

    static let otherSwatch = Swatch(light: 0x8E8E93, dark: 0x8E8E93)

    static var slotCount: Int {
        self.swatches.count
    }

    private static let colors: [Color] = ChartPalette.swatches.map { ChartPalette.dynamicColor($0) }
    static let otherColor: Color = ChartPalette.dynamicColor(ChartPalette.otherSwatch)

    static func color(for slot: Slot) -> Color {
        switch slot {
        case let .index(index):
            guard self.colors.indices.contains(index) else { return self.otherColor }
            return self.colors[index]
        case .other:
            return self.otherColor
        }
    }

    // MARK: - Assignment

    /// Assigns palette slots to series by a stable order: total descending, then name ascending.
    ///
    /// Pinned series claim their slot first (the higher-ranked series wins when two pin the same slot;
    /// the loser falls back to normal assignment). The rest fill the free slots in stable order, and
    /// anything past the last slot folds into `.other`. Duplicate names are summed, and non-finite
    /// totals count as zero so the ordering stays well-defined.
    static func slotAssignment(
        for totals: [(name: String, total: Double)],
        pinnedSlot: (String) -> Int? = { _ in nil }) -> [String: Slot]
    {
        var summed: [String: Double] = [:]
        for entry in totals {
            let total = entry.total.isFinite ? entry.total : 0
            summed[entry.name, default: 0] += total
        }
        let ranked = self.rankedNames(summed)

        var assignment: [String: Slot] = [:]
        var claimed = Set<Int>()
        for name in ranked {
            guard let slot = pinnedSlot(name),
                  self.swatches.indices.contains(slot),
                  !claimed.contains(slot)
            else { continue }
            claimed.insert(slot)
            assignment[name] = .index(slot)
        }

        var nextFree = 0
        for name in ranked where assignment[name] == nil {
            while nextFree < self.slotCount, claimed.contains(nextFree) {
                nextFree += 1
            }
            if nextFree < self.slotCount {
                claimed.insert(nextFree)
                assignment[name] = .index(nextFree)
            } else {
                assignment[name] = .other
            }
        }
        return assignment
    }

    /// Names ordered by total descending, then name ascending.
    static func rankedNames(_ totals: [String: Double]) -> [String] {
        totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }

    // MARK: - Helpers

    private static func dynamicColor(_ swatch: Swatch) -> Color {
        let light = swatch.light
        let dark = swatch.dark
        let nsColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return ChartPalette.nsColor(hex: isDark ? dark : light)
        }
        return Color(nsColor: nsColor)
    }

    private static func nsColor(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}

/// Shared styling and math for the thin dashed daily-average rule drawn over bar charts.
enum ChartReferenceLine {
    static var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 1, dash: [4, 3])
    }
    /// A label color, never a series color, so the rule reads as a reference rather than data.
    static let color = Color(nsColor: .secondaryLabelColor)

    /// Average over the days that have data (positive, finite values); nil when no day has data.
    static func dailyAverage(_ dailyTotals: [Double]) -> Double? {
        let active = dailyTotals.filter { $0.isFinite && $0 > 0 }
        guard !active.isEmpty else { return nil }
        return active.reduce(0, +) / Double(active.count)
    }
}
