// Rebuild the app icon: python3 scripts/normalize-icon.py && swift scripts/generate-icon.swift
// Reads the normalised artwork, not artwork/icon.png directly -- see normalize-icon.py
// for why the raw artwork's shape has to be squared off first.
import AppKit

let destination = URL(fileURLWithPath: "rsyncer/Assets.xcassets/AppIcon.appiconset")
guard let source = NSImage(contentsOfFile: "artwork/icon-normalized.png") else {
    fatalError("Could not load artwork/icon-normalized.png; run scripts/normalize-icon.py from the repository root first")
}
var entries: [[String: String]] = []
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = pointSize * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                    from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(pointSize)x\(pointSize)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(pointSize)x\(pointSize)", "scale": "\(scale)x", "filename": filename])
    }
}
let manifest: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
