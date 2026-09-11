// Rebuild the geometric app icon: swift scripts/generate-icon.swift
import AppKit

let destination = URL(fileURLWithPath: "rsyncer/Assets.xcassets/AppIcon.appiconset")
var entries: [[String: String]] = []
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = pointSize * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let bg = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(red: 0.22, green: 0.42, blue: 0.34, alpha: 1), ending: NSColor(red: 0.08, green: 0.19, blue: 0.16, alpha: 1))!.draw(in: bg, angle: -90)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(64)
        ctx.setStrokeColor(NSColor(red: 0.77, green: 0.92, blue: 0.68, alpha: 1).cgColor)
        ctx.move(to: CGPoint(x: 286, y: 636))
        ctx.addLine(to: CGPoint(x: 740, y: 636))
        ctx.move(to: CGPoint(x: 620, y: 756))
        ctx.addLine(to: CGPoint(x: 740, y: 636))
        ctx.addLine(to: CGPoint(x: 620, y: 516))
        ctx.strokePath()
        ctx.setStrokeColor(NSColor(red: 0.93, green: 0.95, blue: 0.86, alpha: 1).cgColor)
        ctx.move(to: CGPoint(x: 740, y: 388))
        ctx.addLine(to: CGPoint(x: 286, y: 388))
        ctx.move(to: CGPoint(x: 406, y: 508))
        ctx.addLine(to: CGPoint(x: 286, y: 388))
        ctx.addLine(to: CGPoint(x: 406, y: 268))
        ctx.strokePath()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(pointSize)x\(pointSize)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(pointSize)x\(pointSize)", "scale": "\(scale)x", "filename": filename])
    }
}
let manifest: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
