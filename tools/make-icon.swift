// Uygulama ikonunu çizer: swift tools/make-icon.swift <çıktı.png>  (1024x1024)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
c(0x1a1b26).setFill()
NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185).fill()
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(NSBezierPath(roundedRect: body.insetBy(dx: 8, dy: 8), xRadius: 178, yRadius: 178).cgPath)
ctx.setLineWidth(16)
ctx.replacePathWithStrokedPath()
ctx.clip()
NSGradient(starting: c(0x7aa2f7), ending: c(0xbb9af7))!.draw(in: body, angle: -45)
NSGraphicsContext.restoreGraphicsState()

// Üstte bar şeridi, altında döşenmiş pencereler: bir "masaüstü"
let inner = body.insetBy(dx: 120, dy: 120)
let bar = NSRect(x: inner.minX, y: inner.maxY - 90, width: inner.width, height: 90)
c(0x7aa2f7, 0.18).setFill()
let bp = NSBezierPath(roundedRect: bar, xRadius: 45, yRadius: 45)
bp.fill(); c(0x7aa2f7).setStroke(); bp.lineWidth = 12; bp.stroke()
for (i, col) in [c(0x7aa2f7), c(0xbb9af7), c(0x7dcfff)].enumerated() {
    c(0, 0).setFill()
    col.setFill()
    NSBezierPath(ovalIn: NSRect(x: bar.minX + 36 + CGFloat(i) * 58, y: bar.midY - 20, width: 40, height: 40)).fill()
}
c(0x9ece6a).setFill()
NSBezierPath(roundedRect: NSRect(x: bar.maxX - 156, y: bar.midY - 20, width: 120, height: 40), xRadius: 20, yRadius: 20).fill()

let gap: CGFloat = 34
let area = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: bar.minY - gap - inner.minY)
let leftW = (area.width - gap) * 0.55
let tiles = [
    (NSRect(x: area.minX, y: area.minY, width: leftW, height: area.height), c(0x7aa2f7)),
    (NSRect(x: area.minX + leftW + gap, y: area.midY + gap / 2, width: area.width - leftW - gap, height: area.height / 2 - gap / 2), c(0xbb9af7)),
    (NSRect(x: area.minX + leftW + gap, y: area.minY, width: area.width - leftW - gap, height: area.height / 2 - gap / 2), c(0x7dcfff)),
]
for (r, col) in tiles {
    let p = NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40)
    col.withAlphaComponent(0.18).setFill(); p.fill()
    col.setStroke(); p.lineWidth = 12; p.stroke()
}
// Fırça: "rice" etmek
let brush = NSAttributedString(string: "✦", attributes: [.font: NSFont.systemFont(ofSize: 200, weight: .bold), .foregroundColor: c(0xe0af68)])
let s = brush.size()
brush.draw(at: NSPoint(x: tiles[0].0.midX - s.width / 2, y: tiles[0].0.midY - s.height / 2))
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
