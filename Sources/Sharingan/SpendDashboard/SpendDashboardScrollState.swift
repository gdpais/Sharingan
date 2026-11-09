import SwiftUI

extension EnvironmentValues {
    /// True while the Usage & Spend page is scrolling. Hover-driven chart state pauses meanwhile: content
    /// sliding under a still pointer would otherwise re-render a chart on every frame and stall the scroll.
    @Entry var spendDashboardIsScrolling: Bool = false
}

/// Publishes whether the enclosing `ScrollView` is scrolling. A no-op before macOS 15, where hover
/// updates still skip redundant state writes.
struct SpendDashboardScrollPhaseTracker: ViewModifier {
    @Binding var isScrolling: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                if self.isScrolling != phase.isScrolling { self.isScrolling = phase.isScrolling }
            }
        } else {
            content
        }
    }
}
