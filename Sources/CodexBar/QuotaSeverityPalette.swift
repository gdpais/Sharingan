import AppKit
import CodexBarCore
import SwiftUI

/// The one place the app picks colors for quota severity. Compact account rows and provider detail
/// rows tint through it; which level a lane is in comes from `QuotaSeverityBands` in Core.
enum QuotaSeverityPalette {
    /// An explicit "all good" status, for rows that report one.
    static let healthyColor = Color(nsColor: .systemGreen)
    static let warningColor = Color(nsColor: .systemOrange)
    static let criticalColor = Color(nsColor: .systemRed)

    /// Tint for a severity level, or nil for `normal` so the caller keeps its own color (usually the
    /// provider accent).
    static func color(for level: QuotaSeverityLevel) -> Color? {
        switch level {
        case .normal:
            nil
        case .warning:
            self.warningColor
        case .critical, .exhausted:
            self.criticalColor
        }
    }

    static func color(for level: QuotaSeverityLevel, normal: Color) -> Color {
        self.color(for: level) ?? normal
    }
}
