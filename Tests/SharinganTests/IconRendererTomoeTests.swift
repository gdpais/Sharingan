import AppKit
import SharinganCore
import Foundation
import Testing
@testable import Sharingan

@MainActor
struct IconRendererTomoeTests {
    private static func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first {
            $0.pixelsWide == 36 && $0.pixelsHigh == 36
        })
    }

    private static func alphas(_ image: NSImage) throws -> [CGFloat] {
        let rep = try self.bitmap(image)
        var values: [CGFloat] = []
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                values.append((rep.colorAt(x: x, y: y) ?? .clear).alphaComponent)
            }
        }
        return values
    }

    private static func inkedPixels(_ image: NSImage, above threshold: CGFloat = 0.5) throws -> Int {
        try self.alphas(image).count(where: { $0 > threshold })
    }

    @Test
    func `tomoe icons are 18 point templates rendered at 2x`() throws {
        let image = IconRenderer.makeTomoeIcon(
            fills: TomoeIconFills(session: 1, weekly: 0.5, monthly: nil),
            stale: false)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        _ = try Self.bitmap(image)
    }

    @Test
    func `fuller windows draw more ink`() throws {
        func render(_ fraction: Double) -> NSImage {
            IconRenderer.makeTomoeIcon(
                fills: TomoeIconFills(session: fraction, weekly: fraction, monthly: fraction),
                stale: false)
        }
        let full = try Self.inkedPixels(render(1))
        let half = try Self.inkedPixels(render(0.5))
        let exhausted = try Self.inkedPixels(render(0))
        #expect(full > half)
        #expect(half > exhausted)
    }

    @Test
    func `missing windows are fainter than exhausted ones`() throws {
        let exhausted = try Self.alphas(IconRenderer.makeTomoeIcon(
            fills: TomoeIconFills(session: 0, weekly: 0, monthly: 0),
            stale: false))
        let missing = try Self.alphas(IconRenderer.makeTomoeIcon(fills: .empty, stale: false))
        #expect(missing.reduce(0, +) < exhausted.reduce(0, +))
        #expect(missing != exhausted)
    }

    @Test
    func `stale data dims the whole glyph`() throws {
        let fills = TomoeIconFills(session: 1, weekly: 1, monthly: 1)
        let fresh = try Self.alphas(IconRenderer.makeTomoeIcon(fills: fills, stale: false))
        let stale = try Self.alphas(IconRenderer.makeTomoeIcon(fills: fills, stale: true))
        #expect((stale.max() ?? 1) < (fresh.max() ?? 0))
        #expect(stale.reduce(0, +) < fresh.reduce(0, +))
    }

    @Test(arguments: [ProviderStatusIndicator.minor, .maintenance, .major, .critical, .unknown])
    func `status badges show on the tomoe icon`(indicator: ProviderStatusIndicator) throws {
        let fills = TomoeIconFills(session: 1, weekly: 1, monthly: 1)
        let plain = try Self.alphas(IconRenderer.makeTomoeIcon(fills: fills, stale: false))
        let marked = try Self.alphas(IconRenderer.makeTomoeIcon(
            fills: fills,
            stale: false,
            statusIndicator: indicator))
        let cleared = zip(plain, marked).count(where: { $0.0 - $0.1 > 0.25 })
        let glyph = zip(plain, marked).count(where: { $0.0 < 0.05 && $0.1 > 0.5 })
        #expect(cleared >= 4, "Expected the badge halo to clear part of the ring")
        #expect(glyph >= 4, "Expected the badge to stay visible")
    }

    @Test
    func `identical inputs reuse the cached image`() {
        let fills = TomoeIconFills(session: 0.42, weekly: nil, monthly: 0.9)
        let first = IconRenderer.makeTomoeIcon(fills: fills, stale: false)
        let second = IconRenderer.makeTomoeIcon(fills: fills, stale: false)
        let other = IconRenderer.makeTomoeIcon(fills: fills, stale: true)
        #expect(first === second)
        #expect(first !== other)
    }

    /// Developer proof, skipped by default:
    ///   SHARINGAN_TOMOE_ICON_PROOF_DIR=/tmp/tomoe swift test --filter IconRendererTomoeTests
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHARINGAN_TOMOE_ICON_PROOF_DIR"] != nil))
    func `render a tomoe proof sheet`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["SHARINGAN_TOMOE_ICON_PROOF_DIR"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(TomoeIconFills, Bool, ProviderStatusIndicator)] = [
            (TomoeIconFills(session: 1, weekly: 1, monthly: 1), false, .none),
            (TomoeIconFills(session: 0.75, weekly: 0.5, monthly: 0.25), false, .none),
            (TomoeIconFills(session: 0.5, weekly: 0.9, monthly: nil), false, .none),
            (TomoeIconFills(session: 0.1, weekly: 0, monthly: nil), false, .minor),
            (TomoeIconFills(session: 0.6, weekly: 0.3, monthly: nil), true, .major),
            (.empty, false, .none),
        ]
        let scale: CGFloat = 8
        let tile = 18 * scale
        let size = NSSize(width: tile * CGFloat(cases.count), height: tile * 2)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        for (row, background) in [NSColor(white: 0.95, alpha: 1), NSColor(white: 0.12, alpha: 1)].enumerated() {
            background.setFill()
            NSRect(x: 0, y: CGFloat(row) * tile, width: size.width, height: tile).fill()
            let ink = row == 0 ? NSColor.black : NSColor.white
            for (column, input) in cases.enumerated() {
                let icon = IconRenderer.makeTomoeIcon(fills: input.0, stale: input.1, statusIndicator: input.2)
                let rect = NSRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                // Tint the template like the menu bar does, for a light and a dark bar.
                let bounds = NSRect(origin: .zero, size: icon.size)
                let tinted = NSImage(size: icon.size)
                tinted.lockFocus()
                icon.draw(in: bounds)
                ink.set()
                bounds.fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: rect)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("tomoe-icon-proof.png"), options: .atomic)
    }
}
