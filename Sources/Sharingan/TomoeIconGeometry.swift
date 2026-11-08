import SharinganCore
import CoreGraphics
import Foundation

/// Pure geometry for the Tomoe menu bar icon: a ring, a center dot and three comma-shaped tomoe at 120°.
///
/// Each tomoe is a band around the icon center. At every angle along its sweep it covers one radial interval:
/// the union of a round head on the orbit and a tail that tapers to a point behind it. Heads lead clockwise and
/// tails trail counterclockwise. A partial fill covers the head-first part of the band whose area is the
/// requested fraction, so it ends on a straight radial edge and half a quota looks like half the ink.
///
/// All values are in points, in an unflipped (y-up) canvas of `Metrics.canvasSize`.
struct TomoeIconGeometry: Sendable {
    struct Metrics: Equatable, Sendable {
        var canvasSize: Double = 18
        var ringRadius: Double = 8.25
        var ringLineWidth: Double = 1
        var pupilRadius: Double = 1.35
        var orbitRadius: Double = 4.6
        var headRadius: Double = 2.2
        /// How far the tail trails behind the head center, in radians.
        var tailSweep: Double = 78 * Double.pi / 180
        /// The tail tip sits this many head radii outside the orbit, which gives the comma its curl.
        var tailTipOffset: Double = 0.35
        var outlineWidth: Double = 0.5
    }

    struct BandSample: Equatable, Sendable {
        /// Angle relative to the head center; negative is the head's front (clockwise) side.
        let offset: Double
        let inner: Double
        let outer: Double
    }

    struct StatusBadge: Equatable, Sendable {
        /// Drawn as rounded rects with half their shorter side as the corner radius.
        let glyphs: [CGRect]
        /// Cleared before the glyphs are drawn, so the badge stays readable over the ring.
        let halo: CGRect
    }

    static let menuBar = TomoeIconGeometry(metrics: Metrics())

    private static let frontSampleCount = 24
    private static let tailSampleCount = 40
    private static let areaStepCount = 512

    let metrics: Metrics
    /// Outline samples from the head front to the tail tip, denser where the round front turns fastest.
    let samples: [BandSample]
    private let areaOffsets: [Double]
    private let cumulativeAreas: [Double]

    init(metrics: Metrics) {
        self.metrics = metrics
        let front = Self.frontAngle(of: metrics)
        var samples: [BandSample] = []
        for index in 0..<Self.frontSampleCount {
            let turn = Double.pi / 2 * Double(index) / Double(Self.frontSampleCount)
            samples.append(Self.sample(at: front * cos(turn), metrics: metrics))
        }
        for index in 0...Self.tailSampleCount {
            samples.append(Self.sample(
                at: metrics.tailSweep * Double(index) / Double(Self.tailSampleCount),
                metrics: metrics))
        }
        self.samples = samples

        var offsets: [Double] = []
        var areas: [Double] = [0]
        let step = (metrics.tailSweep - front) / Double(Self.areaStepCount)
        var previousDensity = 0.0
        for index in 0...Self.areaStepCount {
            let offset = front + step * Double(index)
            let band = Self.sample(at: offset, metrics: metrics)
            let density = 0.5 * (band.outer * band.outer - band.inner * band.inner)
            if index > 0 {
                areas.append(areas[index - 1] + 0.5 * (previousDensity + density) * step)
            }
            offsets.append(offset)
            previousDensity = density
        }
        self.areaOffsets = offsets
        self.cumulativeAreas = areas
    }

    // MARK: - Layout

    var center: CGPoint {
        CGPoint(x: self.metrics.canvasSize / 2, y: self.metrics.canvasSize / 2)
    }

    var canvasRect: CGRect {
        CGRect(x: 0, y: 0, width: self.metrics.canvasSize, height: self.metrics.canvasSize)
    }

    /// The rect to stroke the ring in; the stroke is centered on `ringRadius`.
    var ringRect: CGRect {
        self.circleRect(radius: self.metrics.ringRadius)
    }

    var pupilRect: CGRect {
        self.circleRect(radius: self.metrics.pupilRadius)
    }

    /// The head center angle for a slot: session at the top, then clockwise every 120°.
    func headAngle(for slot: TomoeIconFills.Slot) -> Double {
        // The slot index stays on its own line: the provider gatekeeper reads π on a line that also mentions the
        // raw value as a reference to the Pi provider.
        let position = Double(slot.rawValue)
        return Double.pi / 2 - position * 2 * Double.pi / 3
    }

    /// Where the band starts: the head's front tangent, relative to the head center.
    var frontOffset: Double {
        Self.frontAngle(of: self.metrics)
    }

    var totalArea: Double {
        self.cumulativeAreas.last ?? 0
    }

    // MARK: - Band

    /// The radial interval the tomoe covers at an angle relative to its head center, or `nil` outside the sweep.
    func band(atOffset offset: Double) -> BandSample? {
        guard offset >= self.frontOffset, offset <= self.metrics.tailSweep else { return nil }
        return Self.sample(at: offset, metrics: self.metrics)
    }

    /// The angle, relative to the head center, where a fill of `fraction` of the tomoe's area ends.
    func fillEndOffset(fraction: Double) -> Double {
        let clamped = fraction.isFinite ? fraction.clamped(to: 0...1) : 0
        let target = clamped * self.totalArea
        guard clamped < 1 else { return self.metrics.tailSweep }
        for index in 1..<self.cumulativeAreas.count where self.cumulativeAreas[index] >= target {
            let low = self.cumulativeAreas[index - 1]
            let span = self.cumulativeAreas[index] - low
            let t = span > 0 ? (target - low) / span : 0
            return self.areaOffsets[index - 1] + t * (self.areaOffsets[index] - self.areaOffsets[index - 1])
        }
        return self.metrics.tailSweep
    }

    /// The area of the part of the band between the head front and `offset`, for tests and sanity checks.
    func area(upTo offset: Double) -> Double {
        guard offset > self.frontOffset else { return 0 }
        guard offset < self.metrics.tailSweep else { return self.totalArea }
        for index in 1..<self.areaOffsets.count where self.areaOffsets[index] >= offset {
            let start = self.areaOffsets[index - 1]
            let t = (offset - start) / (self.areaOffsets[index] - start)
            let low = self.cumulativeAreas[index - 1]
            return low + t * (self.cumulativeAreas[index] - low)
        }
        return self.totalArea
    }

    // MARK: - Points and paths

    /// The tomoe outline as a closed polygon: along the outer edge to the tail tip, then back along the inner edge.
    func outlinePoints(for slot: TomoeIconFills.Slot) -> [CGPoint] {
        self.polygon(samples: self.samples, headAngle: self.headAngle(for: slot))
    }

    /// The filled part of a tomoe, or an empty array when nothing is filled.
    func fillPoints(for slot: TomoeIconFills.Slot, fraction: Double) -> [CGPoint] {
        guard fraction.isFinite, fraction > 0 else { return [] }
        guard fraction < 1 else { return self.outlinePoints(for: slot) }
        let end = self.fillEndOffset(fraction: fraction)
        var samples = self.samples.filter { $0.offset < end }
        samples.append(Self.sample(at: end, metrics: self.metrics))
        return self.polygon(samples: samples, headAngle: self.headAngle(for: slot))
    }

    func outlinePath(for slot: TomoeIconFills.Slot) -> CGPath {
        Self.path(points: self.outlinePoints(for: slot))
    }

    func fillPath(for slot: TomoeIconFills.Slot, fraction: Double) -> CGPath? {
        let points = self.fillPoints(for: slot, fraction: fraction)
        return points.isEmpty ? nil : Self.path(points: points)
    }

    // MARK: - Status badge

    /// Status badges sit in the top-right corner, in the gap after the weekly tail, so no head is covered.
    func statusBadge(for indicator: ProviderStatusIndicator) -> StatusBadge? {
        let size = self.metrics.canvasSize
        switch indicator {
        case .none:
            return nil
        case .minor, .maintenance:
            let dot = CGRect(x: size - 5, y: size - 5, width: 4, height: 4)
            return StatusBadge(glyphs: [dot], halo: dot.insetBy(dx: -1, dy: -1))
        case .major, .critical, .unknown:
            let line = CGRect(x: size - 3, y: size - 5, width: 1.5, height: 4.5)
            let dot = CGRect(x: size - 3, y: size - 7, width: 1.5, height: 1.5)
            return StatusBadge(glyphs: [line, dot], halo: line.union(dot).insetBy(dx: -1, dy: -1))
        }
    }

    // MARK: - Helpers

    private func circleRect(radius: Double) -> CGRect {
        CGRect(
            x: self.metrics.canvasSize / 2 - radius,
            y: self.metrics.canvasSize / 2 - radius,
            width: radius * 2,
            height: radius * 2)
    }

    private func polygon(samples: [BandSample], headAngle: Double) -> [CGPoint] {
        let centerX = self.metrics.canvasSize / 2
        let centerY = self.metrics.canvasSize / 2
        func point(radius: Double, offset: Double) -> CGPoint {
            let angle = headAngle + offset
            return CGPoint(x: centerX + radius * cos(angle), y: centerY + radius * sin(angle))
        }
        let outer = samples.map { point(radius: $0.outer, offset: $0.offset) }
        let inner = samples.reversed().map { point(radius: $0.inner, offset: $0.offset) }
        return outer + inner
    }

    private static func path(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private static func frontAngle(of metrics: Metrics) -> Double {
        -asin(min(1, metrics.headRadius / metrics.orbitRadius))
    }

    /// Union of the head disk and the tail at one angle. Both are a single interval on any ray from the center.
    private static func sample(at offset: Double, metrics: Metrics) -> BandSample {
        let orbit = metrics.orbitRadius
        let head = metrics.headRadius
        var inner = Double.infinity
        var outer = -Double.infinity
        let frontLimit = asin(min(1, head / orbit))
        if abs(offset) <= frontLimit {
            let along = orbit * cos(offset)
            let across = orbit * sin(offset)
            let halfChord = sqrt(max(0, head * head - across * across))
            inner = along - halfChord
            outer = along + halfChord
        }
        if offset >= 0, offset <= metrics.tailSweep {
            let progress = offset / metrics.tailSweep
            let tip = orbit + metrics.tailTipOffset * head
            outer = max(outer, orbit + head + (tip - orbit - head) * progress * progress)
            inner = min(inner, orbit - head + (tip - orbit + head) * pow(progress, 0.85))
        }
        if !inner.isFinite || !outer.isFinite {
            // Outside the sweep: collapse onto the orbit so callers never see an inverted interval.
            return BandSample(offset: offset, inner: orbit, outer: orbit)
        }
        return BandSample(offset: offset, inner: inner, outer: max(inner, outer))
    }
}
