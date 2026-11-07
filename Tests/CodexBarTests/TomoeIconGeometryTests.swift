import CodexBarCore
import CoreGraphics
import Foundation
import Testing
@testable import CodexBar

struct TomoeIconGeometryTests {
    private let geometry = TomoeIconGeometry.menuBar

    private func distanceFromCenter(_ point: CGPoint) -> Double {
        let center = self.geometry.center
        return hypot(Double(point.x - center.x), Double(point.y - center.y))
    }

    @Test
    func `geometry is deterministic`() {
        let rebuilt = TomoeIconGeometry(metrics: TomoeIconGeometry.Metrics())
        #expect(rebuilt.samples == self.geometry.samples)
        for slot in TomoeIconFills.Slot.allCases {
            #expect(rebuilt.outlinePoints(for: slot) == self.geometry.outlinePoints(for: slot))
            #expect(rebuilt.fillPoints(for: slot, fraction: 0.37) == self.geometry.fillPoints(
                for: slot,
                fraction: 0.37))
        }
        #expect(rebuilt.fillEndOffset(fraction: 0.5) == self.geometry.fillEndOffset(fraction: 0.5))
    }

    @Test
    func `heads sit at 120 degrees clockwise from the top`() {
        #expect(abs(self.geometry.headAngle(for: .session) - Double.pi / 2) < 1e-12)
        #expect(abs(self.geometry.headAngle(for: .weekly) + Double.pi / 6) < 1e-12)
        #expect(abs(self.geometry.headAngle(for: .monthly) + 5 * Double.pi / 6) < 1e-12)
    }

    @Test
    func `every tomoe stays inside the ring and the icon bounds`() {
        let metrics = self.geometry.metrics
        let ringInnerEdge = metrics.ringRadius - metrics.ringLineWidth / 2
        let canvas = self.geometry.canvasRect
        #expect(canvas.contains(self.geometry.ringRect.insetBy(
            dx: -CGFloat(metrics.ringLineWidth) / 2,
            dy: -CGFloat(metrics.ringLineWidth) / 2)))
        for slot in TomoeIconFills.Slot.allCases {
            let points = self.geometry.outlinePoints(for: slot)
            #expect(!points.isEmpty)
            for point in points {
                let distance = self.distanceFromCenter(point)
                // Leave room for the outline stroke on both sides.
                #expect(distance + metrics.outlineWidth / 2 < ringInnerEdge)
                #expect(distance - metrics.outlineWidth / 2 > metrics.pupilRadius)
            }
            #expect(canvas.contains(self.geometry.outlinePath(for: slot).boundingBoxOfPath))
        }
    }

    @Test
    func `the band never inverts and tapers to a point at both ends`() throws {
        for sample in self.geometry.samples {
            #expect(sample.inner <= sample.outer)
        }
        let front = try #require(self.geometry.samples.first)
        let tip = try #require(self.geometry.samples.last)
        #expect(abs(front.outer - front.inner) < 1e-6)
        #expect(abs(tip.outer - tip.inner) < 1e-6)
        #expect(self.geometry.band(atOffset: self.geometry.frontOffset - 0.01) == nil)
        #expect(self.geometry.band(atOffset: self.geometry.metrics.tailSweep + 0.01) == nil)
    }

    @Test
    func `fill fractions map to the matching share of the tomoe area`() {
        #expect(self.geometry.totalArea > 0)
        #expect(self.geometry.fillEndOffset(fraction: 0) == self.geometry.frontOffset)
        #expect(self.geometry.fillEndOffset(fraction: 1) == self.geometry.metrics.tailSweep)
        #expect(self.geometry.fillEndOffset(fraction: 2) == self.geometry.metrics.tailSweep)
        #expect(self.geometry.fillEndOffset(fraction: -1) == self.geometry.frontOffset)
        #expect(self.geometry.fillEndOffset(fraction: .nan) == self.geometry.frontOffset)

        var previous = self.geometry.frontOffset
        for step in 1...20 {
            let fraction = Double(step) / 20
            let end = self.geometry.fillEndOffset(fraction: fraction)
            #expect(end > previous)
            let share = self.geometry.area(upTo: end) / self.geometry.totalArea
            #expect(abs(share - fraction) < 0.005)
            previous = end
        }
    }

    @Test
    func `fills grow from the head and empty fills draw nothing`() {
        for slot in TomoeIconFills.Slot.allCases {
            #expect(self.geometry.fillPoints(for: slot, fraction: 0).isEmpty)
            #expect(self.geometry.fillPath(for: slot, fraction: -0.5) == nil)
            #expect(self.geometry.fillPoints(for: slot, fraction: 1) == self.geometry.outlinePoints(for: slot))

            let half = self.geometry.fillPoints(for: slot, fraction: 0.5)
            let outline = self.geometry.outlinePoints(for: slot)
            #expect(!half.isEmpty)
            // The fill starts at the head front, the outline's first point.
            #expect(half.first == outline.first)
            let canvas = self.geometry.canvasRect
            #expect(canvas.contains(Self.boundingBox(half)))
        }
    }

    @Test
    func `status badges stay inside the icon and off the heads`() throws {
        let canvas = self.geometry.canvasRect
        let metrics = self.geometry.metrics
        let headRects = TomoeIconFills.Slot.allCases.map { slot in
            let angle = self.geometry.headAngle(for: slot)
            return CGRect(
                x: metrics.canvasSize / 2 + metrics.orbitRadius * cos(angle) - metrics.headRadius,
                y: metrics.canvasSize / 2 + metrics.orbitRadius * sin(angle) - metrics.headRadius,
                width: metrics.headRadius * 2,
                height: metrics.headRadius * 2)
        }
        #expect(self.geometry.statusBadge(for: .none) == nil)
        let indicators: [ProviderStatusIndicator] = [.minor, .maintenance, .major, .critical, .unknown]
        for indicator in indicators {
            let badge = try #require(self.geometry.statusBadge(for: indicator))
            #expect(!badge.glyphs.isEmpty)
            for glyph in badge.glyphs {
                #expect(canvas.contains(glyph))
                #expect(badge.halo.contains(glyph))
            }
            for headRect in headRects {
                #expect(!badge.halo.intersects(headRect))
            }
        }
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }
}
