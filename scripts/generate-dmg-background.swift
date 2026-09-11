// Generates a Retina-ready Finder background using native text and vector drawing.
import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift generate-dmg-background.swift output.tiff")
}

let size = NSSize(width: 640, height: 420)
let image = NSImage(size: size)
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 420 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSColor(srgbRed: 0.97, green: 0.975, blue: 0.985, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    let ink = NSColor(srgbRed: 0.09, green: 0.14, blue: 0.23, alpha: 1)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 5
    ("Drag Rsyncer into your\nApplications folder" as NSString).draw(
        in: NSRect(x: 40, y: 284, width: 560, height: 86),
        withAttributes: [.font: NSFont.systemFont(ofSize: 27, weight: .semibold),
                         .foregroundColor: ink, .paragraphStyle: paragraph]
    )

    // Finder icon centres are (170, 245) and (470, 245), measured from the top.
    ink.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 3.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 302, y: 175))
    arrow.line(to: NSPoint(x: 338, y: 175))
    arrow.move(to: NSPoint(x: 327, y: 186))
    arrow.line(to: NSPoint(x: 338, y: 175))
    arrow.line(to: NSPoint(x: 327, y: 164))
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
