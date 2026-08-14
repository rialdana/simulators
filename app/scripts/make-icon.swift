// Generates the app icon: a blue-indigo rounded square with two device
// silhouettes and a green "booted" dot. Run: swift make-icon.swift out.png
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1 else {
    fputs("usage: swift make-icon.swift <output.png>\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: rounded square with a diagonal gradient.
let bgRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
NSGradient(colors: [
    NSColor(calibratedRed: 0.32, green: 0.30, blue: 0.94, alpha: 1.0),
    NSColor(calibratedRed: 0.13, green: 0.62, blue: 0.98, alpha: 1.0),
])!.draw(in: bg, angle: -60)

// Back device: translucent filled phone, offset right.
let back = NSBezierPath(roundedRect: NSRect(x: 500, y: 240, width: 250, height: 470), xRadius: 48, yRadius: 48)
NSColor.white.withAlphaComponent(0.35).setFill()
back.fill()

// Front device: bold white outline.
let front = NSBezierPath(roundedRect: NSRect(x: 290, y: 300, width: 280, height: 520), xRadius: 54, yRadius: 54)
NSColor.white.setStroke()
front.lineWidth = 36
front.stroke()

// Green "booted" dot with white ring.
let dot = NSBezierPath(ovalIn: NSRect(x: 610, y: 210, width: 150, height: 150))
NSColor(calibratedRed: 0.20, green: 0.80, blue: 0.35, alpha: 1.0).setFill()
dot.fill()
NSColor.white.setStroke()
dot.lineWidth = 24
dot.stroke()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
