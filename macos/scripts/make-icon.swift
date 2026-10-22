import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let r = CGFloat(pixels)
        NSColor(srgbRed: 0.45, green: 0.26, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: r * 0.08, y: r * 0.08, width: r * 0.84, height: r * 0.84), xRadius: r * 0.19, yRadius: r * 0.19).fill()
        NSColor.white.withAlphaComponent(0.3).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: r * 0.22, y: r * 0.22, width: r * 0.56, height: r * 0.56)); ring.lineWidth = r * 0.025; ring.stroke()
        NSColor.white.setFill()
        for x in [0.4, 0.53] { NSBezierPath(roundedRect: NSRect(x: r * x, y: r * 0.35, width: r * 0.07, height: r * 0.3), xRadius: r * 0.02, yRadius: r * 0.02).fill() }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
