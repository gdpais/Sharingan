import Testing
@testable import Sharingan

struct VerticalScrollPassthroughRouterTests {
    @Test
    func `vertical trackpad gesture goes to the outer scroll view through its momentum`() {
        var router = VerticalScrollPassthroughRouter()
        #expect(router.route(phase: .mayBegin, momentumPhase: .none, deltaX: 0, deltaY: 0) == .inner)
        #expect(router.route(phase: .began, momentumPhase: .none, deltaX: 1, deltaY: -6) == .outer)
        // A later sideways wobble does not switch axes mid-gesture.
        #expect(router.route(phase: .changed, momentumPhase: .none, deltaX: 9, deltaY: -1) == .outer)
        #expect(router.route(phase: .ended, momentumPhase: .none, deltaX: 0, deltaY: 0) == .outer)
        #expect(router.route(phase: .none, momentumPhase: .began, deltaX: 3, deltaY: 0) == .outer)
        #expect(router.route(phase: .none, momentumPhase: .ended, deltaX: 0, deltaY: 0) == .outer)
    }

    @Test
    func `horizontal trackpad gesture stays with the inner scroller`() {
        var router = VerticalScrollPassthroughRouter()
        #expect(router.route(phase: .began, momentumPhase: .none, deltaX: -8, deltaY: 2) == .inner)
        #expect(router.route(phase: .changed, momentumPhase: .none, deltaX: 0, deltaY: -9) == .inner)
        #expect(router.route(phase: .none, momentumPhase: .changed, deltaX: 0, deltaY: -4) == .inner)
    }

    @Test
    func `gesture decides on its first non-zero delta`() {
        var router = VerticalScrollPassthroughRouter()
        #expect(router.route(phase: .began, momentumPhase: .none, deltaX: 0, deltaY: 0) == .inner)
        #expect(router.route(phase: .changed, momentumPhase: .none, deltaX: 0, deltaY: 4) == .outer)
        #expect(router.route(phase: .changed, momentumPhase: .none, deltaX: 7, deltaY: 0) == .outer)
    }

    @Test
    func `a new gesture resets the previous decision`() {
        var router = VerticalScrollPassthroughRouter()
        _ = router.route(phase: .began, momentumPhase: .none, deltaX: 0, deltaY: 5)
        #expect(router.route(phase: .began, momentumPhase: .none, deltaX: 5, deltaY: 1) == .inner)
    }

    @Test
    func `mouse wheel ticks are routed per event`() {
        var router = VerticalScrollPassthroughRouter()
        #expect(router.route(phase: .none, momentumPhase: .none, deltaX: 0, deltaY: -3) == .outer)
        // Shift-wheel arrives as a horizontal delta and keeps scrolling the inner view.
        #expect(router.route(phase: .none, momentumPhase: .none, deltaX: -3, deltaY: 0) == .inner)
    }
}
