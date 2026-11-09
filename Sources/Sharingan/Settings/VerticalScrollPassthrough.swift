import AppKit
import SwiftUI

extension View {
    /// Hands vertical scroll gestures that start over a horizontal-only scroller (a sideways `ScrollView`,
    /// a horizontally scrollable chart) to the nearest enclosing scroll view that can scroll vertically.
    ///
    /// Nested horizontal scrollers latch trackpad gestures that begin over them, so a vertically
    /// scrolling pane stops while the pointer crosses one. Apply this once to the *content* of the pane's
    /// vertical `ScrollView`; it hit-tests every gesture inside that scroll view, so individual scrollers
    /// need no modifier. Horizontal
    /// gestures (and Shift-wheel) keep scrolling the inner scroller as before.
    func verticalScrollPassthrough() -> some View {
        self.background(VerticalScrollPassthroughView().allowsHitTesting(false).accessibilityHidden(true))
    }
}

/// Per-gesture routing decision for scroll events over a horizontal-only scroller.
///
/// A trackpad gesture is decided once, from its first non-zero delta, and the decision holds through
/// its momentum so a flick never switches axes midway. Discrete mouse-wheel ticks (no phases) are
/// decided per event.
struct VerticalScrollPassthroughRouter {
    enum Phase: Equatable {
        /// Discrete mouse-wheel tick without gesture phases.
        case none
        case mayBegin
        case began
        case changed
        case ended
        case cancelled
    }

    enum Route: Equatable {
        /// Leave the event with the horizontal scroller.
        case inner
        /// Send the event to the enclosing vertical scroll view.
        case outer
    }

    private var gestureRoute: Route?

    mutating func route(phase: Phase, momentumPhase: Phase, deltaX: CGFloat, deltaY: CGFloat) -> Route {
        if momentumPhase != .none {
            let route = self.gestureRoute ?? Self.dominantRoute(deltaX: deltaX, deltaY: deltaY) ?? .inner
            if momentumPhase == .ended || momentumPhase == .cancelled {
                self.gestureRoute = nil
            }
            return route
        }

        switch phase {
        case .none:
            self.gestureRoute = nil
            return Self.dominantRoute(deltaX: deltaX, deltaY: deltaY) ?? .inner
        case .mayBegin:
            self.gestureRoute = nil
            return .inner
        case .began, .changed:
            if phase == .began {
                self.gestureRoute = nil
            }
            if self.gestureRoute == nil {
                self.gestureRoute = Self.dominantRoute(deltaX: deltaX, deltaY: deltaY)
            }
            return self.gestureRoute ?? .inner
        case .ended, .cancelled:
            // Keep the decision for the momentum events that may follow.
            return self.gestureRoute ?? .inner
        }
    }

    private static func dominantRoute(deltaX: CGFloat, deltaY: CGFloat) -> Route? {
        if deltaX == 0, deltaY == 0 { return nil }
        return abs(deltaY) > abs(deltaX) ? .outer : .inner
    }
}

extension VerticalScrollPassthroughRouter.Phase {
    init(_ phase: NSEvent.Phase) {
        if phase.contains(.began) {
            self = .began
        } else if phase.contains(.changed) {
            self = .changed
        } else if phase.contains(.ended) {
            self = .ended
        } else if phase.contains(.cancelled) {
            self = .cancelled
        } else if phase.contains(.mayBegin) {
            self = .mayBegin
        } else {
            self = .none
        }
    }
}

private struct VerticalScrollPassthroughView: NSViewRepresentable {
    func makeNSView(context: Context) -> PassthroughView {
        PassthroughView()
    }

    func updateNSView(_ view: PassthroughView, context: Context) {}

    static func dismantleNSView(_ view: PassthroughView, coordinator: ()) {
        view.removeMonitor()
    }

    final class PassthroughView: NSView {
        private var monitor: Any?
        private var router = VerticalScrollPassthroughRouter()
        /// Vertical scroll view the current gesture is handed to; nil when the gesture started over
        /// something that scrolls vertically on its own (or outside this pane).
        private weak var gestureTarget: NSScrollView?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if self.window == nil {
                self.removeMonitor()
            } else {
                self.installMonitor()
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            self.gestureTarget = nil
        }

        private func installMonitor() {
            guard self.monitor == nil else { return }
            self.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window = self.window, event.window === window, !self.isHiddenOrHasHiddenAncestor else {
                return event
            }

            let phase = VerticalScrollPassthroughRouter.Phase(event.phase)
            let momentumPhase = VerticalScrollPassthroughRouter.Phase(event.momentumPhase)
            let startsGesture = phase == .mayBegin || phase == .began || (phase == .none && momentumPhase == .none)
            if startsGesture {
                self.gestureTarget = self.passthroughTarget(for: event, in: window)
            }
            guard let target = self.gestureTarget else { return event }

            let route = self.router.route(
                phase: phase,
                momentumPhase: momentumPhase,
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY)
            if momentumPhase == .ended || momentumPhase == .cancelled {
                self.gestureTarget = nil
            }

            guard route == .outer else { return event }
            target.scrollWheel(with: event)
            return nil
        }

        /// The vertical scroll view to hand a gesture to, when the pointer sits over a scroller that
        /// cannot scroll vertically inside this pane's own scroll view.
        private func passthroughTarget(for event: NSEvent, in window: NSWindow) -> NSScrollView? {
            guard let pane = self.enclosingScrollView,
                  let contentView = window.contentView,
                  let hit = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil)),
                  hit.isDescendant(of: pane)
            else { return nil }

            var view: NSView? = hit
            var passedHorizontalOnly = false
            while let current = view {
                if let scroll = current as? NSScrollView {
                    if Self.canScrollVertically(scroll) {
                        return passedHorizontalOnly ? scroll : nil
                    }
                    passedHorizontalOnly = true
                }
                if current === pane { break }
                view = current.superview
            }
            return nil
        }

        private static func canScrollVertically(_ scroll: NSScrollView) -> Bool {
            guard let document = scroll.documentView else { return false }
            return document.frame.height - scroll.contentView.bounds.height > 0.5
        }
    }
}
