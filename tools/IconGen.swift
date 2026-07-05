import AppKit
import CoreGraphics

// Generates a 1024x1024 macOS app icon (PNG) for Linux VM:
// a modern gradient squircle with a flat-design penguin (Tux).
// Usage: swift IconGen.swift /path/to/out_1024.png

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext

// Flip to top-left origin so layout math reads naturally.
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}
func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx-rx, y: cy-ry, width: rx*2, height: ry*2), transform: nil)
}
func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}

// ---- Background squircle with gradient ----
let inset: CGFloat = 92
let square = CGRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let corner: CGFloat = square.width * 0.2237
let squircle = CGPath(roundedRect: square, cornerWidth: corner, cornerHeight: corner, transform: nil)

// Soft drop shadow for the whole icon.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0, 0, 0, 0.35))
fill(squircle, rgb(60, 70, 200))
ctx.restoreGState()

// Gradient fill (clipped to squircle).
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let grad = CGGradient(colorsSpace: cs, colors: [
    rgb(120, 130, 255),   // top: bright indigo
    rgb(99, 91, 235),
    rgb(67, 56, 202)      // bottom: deep indigo
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: square.minX, y: square.minY),
                       end: CGPoint(x: square.maxX, y: square.maxY), options: [])
// Top glossy highlight.
let hi = CGGradient(colorsSpace: cs, colors: [
    rgb(255, 255, 255, 0.28), rgb(255, 255, 255, 0)
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(hi, startCenter: CGPoint(x: 512, y: 230), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 230), endRadius: 520, options: [])
ctx.restoreGState()

// ---- Penguin (flat Tux) ----
let black = rgb(38, 40, 54)
let belly = rgb(248, 249, 252)
let orange = rgb(255, 162, 38)
let orangeDark = rgb(232, 132, 18)

// Soft shadow under the penguin.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 26, color: rgb(0, 0, 0, 0.28))

// Feet (behind body).
let footY: CGFloat = 786
fill(ellipse(452, footY, 86, 34), orange)
fill(ellipse(572, footY, 86, 34), orange)
ctx.restoreGState()

// Body: head circle + body ellipse + flippers, all black (union by overpaint).
let cx: CGFloat = 512
fill(ellipse(cx, 372, 162, 168), black)          // head
fill(ellipse(cx, 588, 214, 226), black)          // body
// Flippers.
ctx.saveGState()
ctx.translateBy(x: 322, y: 590); ctx.rotate(by: 0.32)
fill(ellipse(0, 0, 56, 168), black); ctx.restoreGState()
ctx.saveGState()
ctx.translateBy(x: 702, y: 590); ctx.rotate(by: -0.32)
fill(ellipse(0, 0, 56, 168), black); ctx.restoreGState()

// Belly (white).
fill(ellipse(cx, 600, 150, 200), belly)

// Face: white eye patches merged.
fill(ellipse(468, 360, 78, 86), belly)
fill(ellipse(556, 360, 78, 86), belly)

// Eyes.
fill(ellipse(474, 372, 30, 34), black)
fill(ellipse(550, 372, 30, 34), black)
fill(ellipse(484, 362, 10, 11), belly)           // catch-lights
fill(ellipse(560, 362, 10, 11), belly)

// Beak.
let beak = CGMutablePath()
beak.move(to: CGPoint(x: 462, y: 430))
beak.addQuadCurve(to: CGPoint(x: cx, y: 408), control: CGPoint(x: 488, y: 404))
beak.addQuadCurve(to: CGPoint(x: 562, y: 430), control: CGPoint(x: 536, y: 404))
beak.addQuadCurve(to: CGPoint(x: cx, y: 452), control: CGPoint(x: 536, y: 452))
beak.addQuadCurve(to: CGPoint(x: 462, y: 430), control: CGPoint(x: 488, y: 452))
beak.closeSubpath()
fill(beak, orange)
fill(ellipse(cx, 432, 64, 9), orangeDark)        // beak split line

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
