#!/usr/bin/env swift
// Generator własnych sprite'ów 2D Rehab Runner (CoreGraphics): niebo, chmura do menu, cień, iskry, kurz, tablica bramki, ikona.
// Modele 3D pochodzą z zewnętrznych paczek (iOS/Resources/LICENSES.md). Uruchom: swift Tools/GenerateArt.swift iOS/Resources/Sprites
// (Ikona aplikacji trafia ręcznie do Assets.xcassets/AppIcon.appiconset.)
// Cała grafika powstaje z tego kodu – brak zewnętrznych zasobów i licencji.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sprites"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let cs = CGColorSpaceCreateDeviceRGB()

func C(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}

/// Rysuje do bitmapy (początek układu: lewy dolny róg) i zapisuje PNG.
func make(_ name: String, _ w: Int, _ h: Int, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    draw(ctx)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name + ".png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

func gradient(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let b = path.boundingBox
    let g = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: b.midX, y: b.maxY), end: CGPoint(x: b.midX, y: b.minY), options: [])
    ctx.restoreGState()
}
func hgradient(_ ctx: CGContext, _ path: CGPath, _ l: CGColor, _ r: CGColor) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let b = path.boundingBox
    let g = CGGradient(colorsSpace: cs, colors: [l, r] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: b.minX, y: b.midY), end: CGPoint(x: b.maxX, y: b.midY), options: [])
    ctx.restoreGState()
}
func outline(_ ctx: CGContext, _ path: CGPath, _ color: CGColor = C(0x1B1530), _ w: CGFloat = 4) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(w); ctx.setLineJoin(.round); ctx.strokePath()
}
func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) { ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath() }
func ellipse(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }
func shine(_ ctx: CGContext, _ r: CGRect, _ rad: CGFloat, _ a: CGFloat = 0.28) { fill(ctx, rr(r, rad), C(0xFFFFFF, a)) }

make("shadow", 128, 40) { c in
    let g = CGGradient(colorsSpace: cs, colors: [C(0x000000, 0.45), C(0x000000, 0)] as CFArray, locations: [0, 1])!
    c.saveGState(); c.translateBy(x: 64, y: 20); c.scaleBy(x: 1, y: 0.3125)
    c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 64, options: [])
    c.restoreGState()
}

// ───────────── Przeszkoda: tablica na bramce (tekstura znaku) ─────────────
make("obs_gantry", 360, 330) { c in
    // wysoka belka znaku: trzeba się ślizgnąć / kucnąć pod nią
    for x in [14.0, 306.0] { let p = rr(CGRect(x: x, y: 0, width: 40, height: 300), 8); hgradient(c, p, C(0x9AA4B5), C(0x5F6A7D)); outline(c, p) }
    let sign = rr(CGRect(x: 0, y: 190, width: 360, height: 120), 22)
    gradient(c, sign, C(0xFF5A5F), C(0xD6303A)); outline(c, sign, C(0x1B1530), 6)
    let inner = rr(CGRect(x: 14, y: 204, width: 332, height: 92), 14); outline(c, inner, C(0xFFFFFF), 4)
    // strzałka w dół
    let ar = CGMutablePath(); ar.move(to: CGPoint(x: 180, y: 214)); ar.addLine(to: CGPoint(x: 226, y: 262)); ar.addLine(to: CGPoint(x: 198, y: 262)); ar.addLine(to: CGPoint(x: 198, y: 288))
    ar.addLine(to: CGPoint(x: 162, y: 288)); ar.addLine(to: CGPoint(x: 162, y: 262)); ar.addLine(to: CGPoint(x: 134, y: 262)); ar.closeSubpath()
    fill(c, ar, C(0xFFFFFF)); outline(c, ar, C(0x1B1530), 3)
    shine(c, CGRect(x: 20, y: 292, width: 320, height: 8), 4, 0.3)
}
// ───────────── Niebo, chmury, droga ─────────────
let skies: [(String, UInt32, UInt32)] = [("park", 0x6EC6FF, 0xFFF3C4), ("city", 0x4C8DFF, 0xBFE3FF), ("sunset", 0x5B3A8C, 0xFFA45C), ("night", 0x0B1030, 0x3A4A9F)]
for s in skies {
    make("sky_\(s.0)", 8, 512) { c in
        let g = CGGradient(colorsSpace: cs, colors: [C(s.1), C(s.2)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: 512), end: .zero, options: [])
    }
}
make("cloud", 260, 110) { c in
    for (x, y, r) in [(70.0, 40.0, 36.0), (120.0, 56.0, 46.0), (180.0, 42.0, 38.0), (130.0, 34.0, 34.0)] { fill(c, ellipse(CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6)), C(0xFFFFFF, 0.92)) }
    fill(c, rr(CGRect(x: 40, y: 6, width: 180, height: 30), 15), C(0xFFFFFF, 0.92))
}
make("spark", 48, 48) { c in
    let g = CGGradient(colorsSpace: cs, colors: [C(0xFFF6C2), C(0xFFD23F, 0.6), C(0xFFD23F, 0)] as CFArray, locations: [0, 0.4, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: 24, y: 24), startRadius: 0, endCenter: CGPoint(x: 24, y: 24), endRadius: 24, options: [])
}
make("dust", 48, 48) { c in
    let g = CGGradient(colorsSpace: cs, colors: [C(0xFFFFFF, 0.8), C(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: 24, y: 24), startRadius: 0, endCenter: CGPoint(x: 24, y: 24), endRadius: 24, options: [])
}
// Ikona aplikacji 1024×1024.
make("AppIcon", 1024, 1024) { c in
    let g = CGGradient(colorsSpace: cs, colors: [C(0x2EC4B6), C(0x3E5BD6)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    // droga w perspektywie
    let road = CGMutablePath(); road.move(to: CGPoint(x: 470, y: 560)); road.addLine(to: CGPoint(x: 554, y: 560)); road.addLine(to: CGPoint(x: 900, y: 0)); road.addLine(to: CGPoint(x: 124, y: 0)); road.closeSubpath()
    fill(c, road, C(0x2B2F55))
    c.setStrokeColor(C(0xFFFFFF, 0.9)); c.setLineWidth(14); c.setLineDash(phase: 0, lengths: [60, 50]); c.move(to: CGPoint(x: 512, y: 560)); c.addLine(to: CGPoint(x: 512, y: 0)); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
    // moneta
    let coin = ellipse(CGRect(x: 332, y: 330, width: 360, height: 360)); gradient(c, coin, C(0xFFE066), C(0xF2A900)); outline(c, coin, C(0x9B6A00), 20)
    let star = CGMutablePath()
    for k in 0..<10 { let a = Double(k) * .pi / 5 - .pi / 2; let rad = k % 2 == 0 ? 120.0 : 52.0
        let p = CGPoint(x: 512 + CGFloat(cos(a) * rad), y: 510 + CGFloat(sin(a) * rad)); k == 0 ? star.move(to: p) : star.addLine(to: p) }
    star.closeSubpath(); fill(c, star, C(0xFFF6C2))
}
print("Wygenerowano grafikę do \(outDir)")
