import SwiftUI

/// Share the saved width with the legacy sidebar while letting the native divider handle dragging.
struct SettingsSidebarSizing: ViewModifier {
    /// How long the divider must rest before the new width is saved.
    static let saveDelay: Duration = .milliseconds(300)

    @Binding var width: Double
    @State private var pendingSave: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { newWidth in
                // Ignore transient zero/undersized measurements while the split view is being attached.
                guard newWidth >= SettingsPane.sidebarMinWidth,
                      newWidth <= SettingsPane.sidebarMaxWidth else { return }
                // Save once the drag settles. Writing the stored width on every frame re-renders the whole
                // Settings view and moves the column's ideal width mid-drag, which makes the divider lag.
                // Cancel before the unchanged-width check: a drag that ends back at the saved width must
                // drop the save an earlier frame queued, or that stale width wins.
                self.pendingSave?.cancel()
                self.pendingSave = nil
                guard abs(self.width - newWidth) > 0.5 else { return }
                self.pendingSave = Task { @MainActor in
                    try? await Task.sleep(for: Self.saveDelay)
                    guard !Task.isCancelled else { return }
                    self.width = newWidth
                }
            }
            // Keep this last so the column preference reaches NavigationSplitView.
            .navigationSplitViewColumnWidth(
                min: SettingsPane.sidebarMinWidth,
                ideal: min(max(self.width, SettingsPane.sidebarMinWidth), SettingsPane.sidebarMaxWidth),
                max: SettingsPane.sidebarMaxWidth)
    }
}
