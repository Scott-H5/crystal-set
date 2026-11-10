// make-icon.swift
//
// Draws Crystal Set's app icon from simple shapes, so the artwork is
// original and belongs to the project. No clip art or Apple symbols are used.
//
// The picture is a crystal set, the simple home-built radio:
//   - a deep blue background, darker toward the bottom
//   - a copper coil of wire lying across the lower middle
//   - a pale blue, faceted crystal standing on top of the coil
//   - white curved lines spreading out to both sides of the crystal's tip,
//     like ripples: radio waves. (They go sideways on purpose. Stacked
//     above the tip, they'd look like the Wi-Fi symbol.)
//
// Run it from the project folder:
//   bash icon/make-icon.sh
// which runs this script and then makes the Mac's .icns file. This script
// writes two 1024 x 1024 pictures:
//   - iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png: the iPhone icon.
//     Square and filled to the edges; iOS rounds the corners itself.
//   - icon/build/AppIcon-mac.png: the Mac icon. macOS doesn't round icons,
//     so this one is drawn as a smaller rounded square with a soft shadow,
//     the shape Apple's guidelines ask Mac icons to have.
//
// To change the design, edit the numbers and colors below and run it again.
// Positions are in pixels on a 1024 x 1024 canvas, measured from the
// BOTTOM left corner (Core Graphics counts upward).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024

// A color from 0-255 red, green and blue values, like a paint chip.
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// MARK: - The picture

/// Draws the whole icon, filling a 1024 x 1024 square.
func drawArtwork(_ c: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Background: deep blue, lighter at the top, darker at the bottom.
    let sky = CGGradient(colorsSpace: space,
                         colors: [rgb(38, 72, 150), rgb(10, 24, 66)] as CFArray,
                         locations: [0, 1])!
    c.drawLinearGradient(sky, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])

    drawCoil(c, space: space)
    drawWaves(c)
    drawCrystal(c)
}

/// The coil: a dark tube with copper windings wrapped around it.
func drawCoil(_ c: CGContext, space: CGColorSpace) {
    let left = 222.0, right = 802.0
    let centerY = 360.0, height = 190.0

    // The tube the wire is wound on, slightly wider than the windings.
    let tube = CGRect(x: left - 26, y: centerY - height / 2 + 24, width: right - left + 52, height: height - 48)
    c.setFillColor(rgb(58, 34, 20))
    c.addPath(CGPath(roundedRect: tube, cornerWidth: 30, cornerHeight: 30, transform: nil))
    c.fillPath()

    // The windings: tall rounded bars side by side, each shaded like
    // round copper wire (dark edges, a bright stripe in the middle).
    let copper = CGGradient(colorsSpace: space,
                            colors: [rgb(120, 58, 22), rgb(214, 128, 64), rgb(255, 205, 150),
                                     rgb(214, 128, 64), rgb(120, 58, 22)] as CFArray,
                            locations: [0, 0.3, 0.5, 0.7, 1])!
    let turns = 13
    let gap = 6.0
    let barWidth = (right - left - gap * Double(turns - 1)) / Double(turns)
    for i in 0..<turns {
        let x = left + Double(i) * (barWidth + gap)
        let bar = CGRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
        c.saveGState()
        c.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        c.clip()
        // Shaded top to bottom, so each turn looks round.
        c.drawLinearGradient(copper, start: CGPoint(x: x, y: bar.maxY), end: CGPoint(x: x, y: bar.minY), options: [])
        c.restoreGState()
    }
}

/// The crystal: a six-sided gem standing on the coil, pointed at the top.
func drawCrystal(_ c: CGContext) {
    let cx = 512.0
    let base = 440.0   // bottom point, resting on the coil
    let shoulder = 560.0, top = 690.0
    let half = 78.0    // half the crystal's width

    // Corner points, going around the outline.
    let bottom = CGPoint(x: cx, y: base)
    let lowLeft = CGPoint(x: cx - half, y: base + 50)
    let highLeft = CGPoint(x: cx - half, y: shoulder)
    let peak = CGPoint(x: cx, y: top)
    let highRight = CGPoint(x: cx + half, y: shoulder)
    let lowRight = CGPoint(x: cx + half, y: base + 50)
    let middleTop = CGPoint(x: cx, y: shoulder + 20)
    let middleBottom = CGPoint(x: cx, y: base + 70)

    // Facets, each a slightly different shade of pale blue, as if lit from the left.
    func facet(_ points: [CGPoint], _ color: CGColor) {
        c.beginPath()
        c.addLines(between: points)
        c.closePath()
        c.setFillColor(color)
        c.fillPath()
    }
    facet([highLeft, peak, middleTop], rgb(235, 248, 255))                     // top left: brightest
    facet([middleTop, peak, highRight], rgb(170, 215, 245))                    // top right
    facet([lowLeft, highLeft, middleTop, middleBottom], rgb(200, 232, 252))    // left side
    facet([middleBottom, middleTop, highRight, lowRight], rgb(130, 185, 230))  // right side: in shadow
    facet([bottom, lowLeft, middleBottom], rgb(150, 200, 238))                 // bottom left
    facet([bottom, middleBottom, lowRight], rgb(105, 160, 215))                // bottom right

    // A white outline, so the crystal stands out from the background.
    c.beginPath()
    c.addLines(between: [bottom, lowLeft, highLeft, peak, highRight, lowRight])
    c.closePath()
    c.setStrokeColor(rgb(255, 255, 255, 0.9))
    c.setLineWidth(8)
    c.setLineJoin(.round)
    c.strokePath()
}

/// Three curved lines on each side of the crystal's tip, spreading outward
/// like ripples: radio waves.
func drawWaves(_ c: CGContext) {
    let tip = CGPoint(x: 512, y: 690)
    c.setStrokeColor(rgb(255, 255, 255, 0.95))
    c.setLineWidth(24)
    c.setLineCap(.round)
    // Each wave is part of a circle around the tip. Angles are in radians:
    // 0 points right and .pi points left; 0.55 either side makes a short arc.
    for radius in [80.0, 145.0, 210.0] {
        for direction in [0.0, Double.pi] {
            c.beginPath()
            c.addArc(center: tip, radius: radius,
                     startAngle: direction - 0.55, endAngle: direction + 0.55, clockwise: false)
            c.strokePath()
        }
    }
}

// MARK: - Saving

/// Makes a blank 1024 x 1024 canvas. `opaque` leaves out transparency,
/// which iPhone icons must not have.
func makeCanvas(opaque: Bool) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue
                                 : CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func savePNG(_ c: CGContext, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, c.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("Wrote \(path)")
}

// iPhone: the artwork fills the whole square.
let phone = makeCanvas(opaque: true)
drawArtwork(phone)
savePNG(phone, to: "iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

// Mac: an 824-pixel rounded square in the middle, with a soft shadow below.
let mac = makeCanvas(opaque: false)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileShape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
mac.saveGState()
mac.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0, 0, 0, 0.45))
mac.addPath(tileShape)
mac.setFillColor(rgb(10, 24, 66))
mac.fillPath()
mac.restoreGState()
mac.addPath(tileShape)
mac.clip()
// Shrink the artwork to fit the rounded square.
mac.translateBy(x: tile.minX, y: tile.minY)
mac.scaleBy(x: tile.width / 1024, y: tile.height / 1024)
drawArtwork(mac)
savePNG(mac, to: "icon/build/AppIcon-mac.png")
