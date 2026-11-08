import AppKit
import SharinganCore

private final class TomoeIconCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSImage>()

    init(limit: Int) {
        self.cache.countLimit = limit
    }

    func image(for key: NSString) -> NSImage? {
        self.cache.object(forKey: key)
    }

    func set(_ image: NSImage, for key: NSString) {
        self.cache.setObject(image, forKey: key)
    }
}

extension IconRenderer {
    /// Alphas for the Tomoe icon, on the same ladder as the meter styles' track, stroke and fill.
    enum TomoeInk {
        static let ring: CGFloat = 0.9
        static let pupil: CGFloat = 1
        static let fill: CGFloat = 1
        static let track: CGFloat = 0.22
        static let outline: CGFloat = 0.6
        static let missingOutline: CGFloat = 0.3
        /// Stale or errored data dims the whole glyph, like the meter styles' stale fill.
        static let staleFactor: CGFloat = 0.55
    }

    private static let tomoeIconCache = TomoeIconCache(limit: 128)

    /// The opt-in Tomoe style: a ring, a center dot and three tomoe (session, weekly and monthly, clockwise from
    /// the top) filled to each window's fraction. A window the provider lacks is a faint outline; an exhausted one
    /// is an outline over a faint track. Monochrome template image, 18×18 pt rendered at 2×.
    static func makeTomoeIcon(
        fills: TomoeIconFills,
        stale: Bool,
        statusIndicator: ProviderStatusIndicator = .none) -> NSImage
    {
        let key = NSString(string: "\(fills.signature)|\(stale ? 1 : 0)|\(statusIndicator.rawValue)")
        if let cached = self.tomoeIconCache.image(for: key) {
            return cached
        }
        let image = self.renderImage {
            self.drawTomoe(fills: fills, stale: stale, statusIndicator: statusIndicator, geometry: .menuBar)
        }
        self.tomoeIconCache.set(image, for: key)
        return image
    }

    private static func drawTomoe(
        fills: TomoeIconFills,
        stale: Bool,
        statusIndicator: ProviderStatusIndicator,
        geometry: TomoeIconGeometry)
    {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let base = NSColor.labelColor
        let dim = stale ? TomoeInk.staleFactor : 1
        func ink(_ alpha: CGFloat) -> CGColor {
            base.withAlphaComponent(alpha * dim).cgColor
        }

        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(ink(TomoeInk.ring))
        ctx.setLineWidth(CGFloat(geometry.metrics.ringLineWidth))
        ctx.strokeEllipse(in: geometry.ringRect)
        ctx.setFillColor(ink(TomoeInk.pupil))
        ctx.fillEllipse(in: geometry.pupilRect)

        ctx.setLineWidth(CGFloat(geometry.metrics.outlineWidth))
        for slot in TomoeIconFills.Slot.allCases {
            let outline = geometry.outlinePath(for: slot)
            guard let fraction = fills.fraction(for: slot) else {
                ctx.setStrokeColor(ink(TomoeInk.missingOutline))
                ctx.addPath(outline)
                ctx.strokePath()
                continue
            }
            ctx.setFillColor(ink(TomoeInk.track))
            ctx.addPath(outline)
            ctx.fillPath()
            if let filled = geometry.fillPath(for: slot, fraction: fraction) {
                ctx.setFillColor(ink(TomoeInk.fill))
                ctx.addPath(filled)
                ctx.fillPath()
            }
            ctx.setStrokeColor(ink(TomoeInk.outline))
            ctx.addPath(outline)
            ctx.strokePath()
        }
        ctx.restoreGState()

        if let badge = geometry.statusBadge(for: statusIndicator) {
            self.drawTomoeStatusBadge(badge, in: ctx)
        }
    }

    private static func drawTomoeStatusBadge(_ badge: TomoeIconGeometry.StatusBadge, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        // The fill color is ignored by .clear; it only drives the path fill operation.
        NSColor.black.setFill()
        let haloRadius = min(badge.halo.width, badge.halo.height) / 2
        NSBezierPath(roundedRect: badge.halo, xRadius: haloRadius, yRadius: haloRadius).fill()
        ctx.restoreGState()

        NSColor.labelColor.setFill()
        for glyph in badge.glyphs {
            let radius = min(glyph.width, glyph.height) / 2
            NSBezierPath(roundedRect: glyph, xRadius: radius, yRadius: radius).fill()
        }
    }
}
