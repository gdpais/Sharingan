#!/usr/bin/env swift
// Renders the Sharingan app icon art (Icon.icon/Assets/sharingan.png): a red iris with three tomoe, the same
// comma geometry as the menu bar Tomoe style (Sources/Sharingan/TomoeIconGeometry.swift), on the icon's black fill.
//
// Usage: swift Scripts/render_icon_art.swift [output.png]   (then run Scripts/build_icon.sh)

import AppKit
import CoreGraphics
import Foundation

let size = 1024.0
let center = CGPoint(x: size / 2, y: size / 2)
// Menu bar metrics are in an 18 pt canvas; scale them up around a slightly larger iris for the app icon.
let unit = size / 18 * 0.9

let irisRadius = 8.0 * unit
let ringWidth = 0.55 * unit
let orbitRadius = 4.6 * unit
let orbitLineWidth = 0.22 * unit
let pupilRadius = 1.35 * unit
let headRadius = 1.5 * unit
let tailSweep = 72 * Double.pi / 180
let tailTipOffset = 0.35

func sample(at offset: Double) -> (inner: Double, outer: Double)? {
    var inner = Double.infinity
    var outer = -Double.infinity
    let frontLimit = asin(min(1, headRadius / orbitRadius))
    if abs(offset) <= frontLimit {
        let along = orbitRadius * cos(offset)
        let across = orbitRadius * sin(offset)
        let halfChord = sqrt(max(0, headRadius * headRadius - across * across))
        inner = along - halfChord
        outer = along + halfChord
    }
    if offset >= 0, offset <= tailSweep {
        let progress = offset / tailSweep
        let tip = orbitRadius + tailTipOffset * headRadius
        outer = max(outer, orbitRadius + headRadius + (tip - orbitRadius - headRadius) * progress * progress)
        inner = min(inner, orbitRadius - headRadius + (tip - orbitRadius + headRadius) * pow(progress, 0.85))
    }
    guard inner.isFinite, outer.isFinite else { return nil }
    return (inner, max(inner, outer))
}

func tomoePath(headAngle: Double) -> CGPath {
    let front = -asin(min(1, headRadius / orbitRadius))
    var offsets: [Double] = []
    for index in 0..<96 {
        offsets.append(front * cos(Double.pi / 2 * Double(index) / 96))
    }
    for index in 0...240 {
        offsets.append(tailSweep * Double(index) / 240)
    }
    let bands = offsets.compactMap { offset in sample(at: offset).map { (offset, $0.inner, $0.outer) } }
    func point(_ radius: Double, _ offset: Double) -> CGPoint {
        let angle = headAngle + offset
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    let path = CGMutablePath()
    let outer = bands.map { point($0.2, $0.0) }
    let inner = bands.reversed().map { point($0.1, $0.0) }
    path.addLines(between: outer + inner)
    path.closeSubpath()
    return path
}

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

let output = CommandLine.arguments.dropFirst().first ?? "Icon.icon/Assets/sharingan.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("context") }

// Background: the icon's black fill.
ctx.setFillColor(color(0, 0, 0))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Iris: radial red gradient, brighter toward the middle.
let irisRect = CGRect(x: center.x - irisRadius, y: center.y - irisRadius, width: irisRadius * 2, height: irisRadius * 2)
ctx.saveGState()
ctx.addEllipse(in: irisRect)
ctx.clip()
let iris = CGGradient(
    colorsSpace: space,
    colors: [color(0.93, 0.13, 0.15), color(0.78, 0.04, 0.08), color(0.42, 0.0, 0.03)] as CFArray,
    locations: [0, 0.62, 1])!
ctx.drawRadialGradient(
    iris, startCenter: center, startRadius: 0, endCenter: center, endRadius: irisRadius, options: [])
ctx.restoreGState()

let ink = color(0.04, 0.02, 0.02)

// Outer ring and the faint orbit the tomoe ride on.
ctx.setStrokeColor(ink)
ctx.setLineWidth(ringWidth)
ctx.strokeEllipse(in: irisRect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
ctx.setStrokeColor(color(0.18, 0.0, 0.02, 0.75))
ctx.setLineWidth(orbitLineWidth)
ctx.strokeEllipse(in: CGRect(
    x: center.x - orbitRadius, y: center.y - orbitRadius, width: orbitRadius * 2, height: orbitRadius * 2))

// Pupil and three tomoe, heads at 12, 4 and 8 o'clock with tails trailing counterclockwise.
ctx.setFillColor(ink)
ctx.fillEllipse(in: CGRect(
    x: center.x - pupilRadius, y: center.y - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2))
for slot in 0..<3 {
    ctx.addPath(tomoePath(headAngle: Double.pi / 2 - Double(slot) * 2 * Double.pi / 3))
    ctx.fillPath()
}

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try data.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
