import SwiftUI
import AppKit

/// The app artwork's straight outgoing arrow and curved return arrow.
/// Shared vector geometry keeps the small menu bar mark and sidebar in step.
struct BrandMark: Shape {
    var showsFaces = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 25, y: 21))
        path.addLine(to: CGPoint(x: 66, y: 21))
        path.addLine(to: CGPoint(x: 66, y: 12))
        path.addCurve(to: CGPoint(x: 76, y: 8), control1: CGPoint(x: 66, y: 5), control2: CGPoint(x: 71, y: 3))
        path.addLine(to: CGPoint(x: 94, y: 25))
        path.addQuadCurve(to: CGPoint(x: 94, y: 35), control: CGPoint(x: 100, y: 30))
        path.addLine(to: CGPoint(x: 77, y: 51))
        path.addCurve(to: CGPoint(x: 67, y: 47), control1: CGPoint(x: 71, y: 57), control2: CGPoint(x: 67, y: 54))
        path.addLine(to: CGPoint(x: 67, y: 39))
        path.addLine(to: CGPoint(x: 25, y: 39))
        path.addCurve(to: CGPoint(x: 25, y: 21), control1: CGPoint(x: 10, y: 40), control2: CGPoint(x: 10, y: 21))
        path.closeSubpath()

        path.move(to: CGPoint(x: 8, y: 46))
        path.addLine(to: CGPoint(x: 29, y: 43))
        path.addCurve(to: CGPoint(x: 35, y: 52), control1: CGPoint(x: 38, y: 41), control2: CGPoint(x: 40, y: 47))
        path.addLine(to: CGPoint(x: 31, y: 58))
        path.addCurve(to: CGPoint(x: 81, y: 58), control1: CGPoint(x: 47, y: 75), control2: CGPoint(x: 69, y: 75))
        path.addCurve(to: CGPoint(x: 94, y: 69), control1: CGPoint(x: 89, y: 47), control2: CGPoint(x: 102, y: 57))
        path.addCurve(to: CGPoint(x: 19, y: 74), control1: CGPoint(x: 77, y: 97), control2: CGPoint(x: 40, y: 99))
        path.addLine(to: CGPoint(x: 15, y: 79))
        path.addCurve(to: CGPoint(x: 7, y: 76), control1: CGPoint(x: 12, y: 84), control2: CGPoint(x: 8, y: 82))
        path.addLine(to: CGPoint(x: 2, y: 55))
        path.addQuadCurve(to: CGPoint(x: 8, y: 46), control: CGPoint(x: 0, y: 48))
        path.closeSubpath()

        if showsFaces {
            path.addEllipse(in: CGRect(x: 61, y: 25, width: 5, height: 9))
            path.addEllipse(in: CGRect(x: 73, y: 24, width: 5, height: 9))
            // Small smiling eyes on the returning arrow.
            for x in [14.0, 25.0] {
                path.move(to: CGPoint(x: x, y: 61))
                path.addCurve(to: CGPoint(x: x + 7, y: 64), control1: CGPoint(x: x + 1, y: 53), control2: CGPoint(x: x + 10, y: 56))
                path.addQuadCurve(to: CGPoint(x: x + 4, y: 63), control: CGPoint(x: x + 5, y: 67))
                path.addQuadCurve(to: CGPoint(x: x + 2, y: 62), control: CGPoint(x: x + 5, y: 59))
                path.addQuadCurve(to: CGPoint(x: x, y: 61), control: CGPoint(x: x - 1, y: 64))
                path.closeSubpath()
            }
        }

        let scale = min(rect.width, rect.height) / 100
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                             tx: rect.midX - 50 * scale, ty: rect.midY - 47 * scale))
    }
}

enum MenuBarBrandMark {
    static let idle = makeImage(active: false)
    static let active = makeImage(active: true)

    private static func makeImage(active: Bool) -> NSImage {
        let size = NSSize(width: active ? 25 : 20, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(BrandMark(showsFaces: false).path(in: CGRect(x: 0, y: 0, width: 20, height: 18)).cgPath)
            context.fillPath()
            if active {
                context.fillEllipse(in: CGRect(x: 21, y: 7, width: 3, height: 3))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
