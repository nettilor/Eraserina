// Generates AppIcon.iconset/ for Eraserina: a cute eraser wiping a blue
// background away to the transparency checkerboard.
// Run with:  swift MakeIcon.swift   (build.sh does this automatically)

import AppKit
import CoreGraphics

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icons float inside a transparent margin.
let inset: CGFloat = 100
let card = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let squircle = CGPath(roundedRect: card, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// 1) Checkerboard base — the transparency the eraser reveals.
ctx.setFillColor(hex(0xFFFFFF))
ctx.fill(card)
let cell = card.width / 8
ctx.setFillColor(hex(0xDEE2E6))
for row in 0..<8 {
    for col in 0..<8 where (row + col) % 2 == 0 {
        ctx.fill(CGRect(x: card.minX + CGFloat(col) * cell,
                        y: card.minY + CGFloat(row) * cell, width: cell, height: cell))
    }
}

// 2) The "background" still being erased: blue sky over the top-left of a
//    gentle diagonal curve, with a little sun.
let boundary = CGMutablePath()
boundary.move(to: CGPoint(x: card.minX, y: card.maxY))
boundary.addLine(to: CGPoint(x: card.maxX, y: card.maxY))
boundary.addCurve(to: CGPoint(x: card.minX, y: card.minY),
                  control1: CGPoint(x: 680, y: 660),
                  control2: CGPoint(x: 360, y: 340))
boundary.closeSubpath()

ctx.saveGState()
ctx.addPath(boundary)
ctx.clip()
let grad = CGGradient(colorsSpace: space,
                      colors: [hex(0x8BD3FF), hex(0x5C7CFA)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: card.minX, y: card.maxY),
                       end: CGPoint(x: card.maxX * 0.7, y: card.minY),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.setFillColor(hex(0xFFD43B))
ctx.fillEllipse(in: CGRect(x: 220, y: 690, width: 160, height: 160))
ctx.restoreGState()

// 3) The eraser: pink rounded block at 45° with a darker sleeve and a
//    kawaii face, resting on the erased edge.
ctx.saveGState()
ctx.translateBy(x: 540, y: 500)
ctx.rotate(by: .pi / 4)

let body = CGRect(x: -250, y: -130, width: 500, height: 260)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 62, cornerHeight: 62, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: hex(0x000000, 0.30))
ctx.addPath(bodyPath)
ctx.setFillColor(hex(0xFF8FB3))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.setFillColor(hex(0xE8598B))                       // sleeve on the tail end
ctx.fill(CGRect(x: -250, y: -130, width: 150, height: 260))
ctx.setFillColor(hex(0xFFFFFF, 0.22))                 // soft top highlight
ctx.fill(CGRect(x: -250, y: 82, width: 500, height: 30))
ctx.restoreGState()

let fx: CGFloat = 90                                  // face center on the pink part
ctx.setFillColor(hex(0x343A40))
ctx.fillEllipse(in: CGRect(x: fx - 68 - 23, y: 2, width: 46, height: 46))
ctx.fillEllipse(in: CGRect(x: fx + 68 - 23, y: 2, width: 46, height: 46))
ctx.setFillColor(hex(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: fx - 68 - 3, y: 26, width: 16, height: 16))
ctx.fillEllipse(in: CGRect(x: fx + 68 - 3, y: 26, width: 16, height: 16))
ctx.setStrokeColor(hex(0x343A40))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: fx, y: 6), radius: 38,
           startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
ctx.strokePath()
ctx.setFillColor(hex(0xFF5C8A, 0.55))
ctx.fillEllipse(in: CGRect(x: fx - 130 - 27, y: -44, width: 54, height: 34))
ctx.fillEllipse(in: CGRect(x: fx + 130 - 27, y: -44, width: 54, height: 34))
ctx.restoreGState()

// 4) Sparkles where the background has been cleaned away.
func sparkle(center: CGPoint, r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: center.x, y: center.y + r))
    for i in 0..<4 {
        let a0 = CGFloat.pi / 2 - CGFloat(i) * .pi / 2
        let a1 = a0 - .pi / 2
        let mid = (a0 + a1) / 2
        let inner = r * 0.25
        p.addQuadCurve(to: CGPoint(x: center.x + r * cos(a1), y: center.y + r * sin(a1)),
                       control: CGPoint(x: center.x + inner * cos(mid), y: center.y + inner * sin(mid)))
    }
    p.closeSubpath()
    return p
}

let sparkles: [(CGPoint, CGFloat, CGColor)] = [
    (CGPoint(x: 830, y: 350), 44, hex(0xFF8FB3)),
    (CGPoint(x: 700, y: 205), 26, hex(0xFF8FB3)),
    (CGPoint(x: 450, y: 855), 26, hex(0xFFFFFF, 0.95)),
    (CGPoint(x: 205, y: 560), 20, hex(0xFFFFFF, 0.95)),
]
for (c, r, col) in sparkles {
    ctx.addPath(sparkle(center: c, r: r))
    ctx.setFillColor(col)
    ctx.fillPath()
}

ctx.restoreGState()   // squircle clip

let master = ctx.makeImage()!

// Write the .iconset — build.sh turns it into AppIcon.icns with iconutil.
func scaled(_ image: CGImage, to n: Int) -> CGImage {
    let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
                      bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
    return c.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try data.write(to: url)
}

let iconsetURL = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in entries {
    try writePNG(scaled(master, to: size), to: iconsetURL.appendingPathComponent(name))
}
print("Wrote AppIcon.iconset")
