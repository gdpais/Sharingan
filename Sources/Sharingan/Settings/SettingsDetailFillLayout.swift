import SwiftUI

/// Fills whatever space the Settings detail column offers without measuring the pane inside it.
///
/// The detail column's hosting view asks SwiftUI for its minimum size on every layout pass. Answered
/// normally, that lays out the whole pane at zero width (every line of text wrapping, every `ViewThatFits`
/// trying each child), which made live window and sidebar resizes lag. The window already enforces its
/// minimum size through `SettingsWindowSizing`, so this layout reports the offered size, takes no part in
/// alignment, and lays the pane out once at its real frame.
struct SettingsDetailFillLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    /// The default implementations merge the subviews' alignment guides, which measures the pane again.
    func explicitAlignment(
        of _: HorizontalAlignment,
        in _: CGRect,
        proposal _: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()) -> CGFloat?
    {
        nil
    }

    func explicitAlignment(
        of _: VerticalAlignment,
        in _: CGRect,
        proposal _: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()) -> CGFloat?
    {
        nil
    }
}
