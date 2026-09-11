import AppKit
import Combine

/// Owned by the app delegate so progress survives closing the main window.
@MainActor
final class DockProgressController {
    private let view = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private var observation: AnyCancellable?
    private var animation: AnyCancellable?

    init(store: AppStore) {
        observation = Publishers.CombineLatest4(store.$activePairID, store.$isPreview,
                                                store.$progress, store.$isPaused)
            .receive(on: RunLoop.main)
            .sink { [weak self] pairID, preview, progress, paused in
                self?.update(visible: pairID != nil && !preview, progress: progress, paused: paused)
            }
    }

    private func update(visible: Bool, progress: Double?, paused: Bool) {
        let tile = NSApp.dockTile
        guard visible else {
            animation = nil
            if tile.contentView === view {
                tile.contentView = nil
                tile.display()
            }
            return
        }
        view.icon = NSApp.applicationIconImage
        view.progress = progress.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        view.paused = paused
        tile.contentView = view
        if progress == nil && !paused {
            if animation == nil {
                animation = Timer.publish(every: 0.1, on: .main, in: .common)
                    .autoconnect()
                    .sink { [weak self] _ in
                        guard let self else { return }
                        self.view.phase += 0.1
                        NSApp.dockTile.display()
                    }
            }
        } else {
            animation = nil
        }
        tile.display()
    }
}

@MainActor
private final class DockProgressView: NSView {
    var icon: NSImage?
    var progress: Double?
    var paused = false
    var phase = 0.0

    override func draw(_ dirtyRect: NSRect) {
        icon?.draw(in: bounds)

        let track = NSRect(x: bounds.width * 0.14, y: bounds.height * 0.1,
                           width: bounds.width * 0.72, height: bounds.height * 0.11)
        let outline = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        NSColor.black.withAlphaComponent(0.8).setFill()
        outline.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        outline.lineWidth = bounds.width / 128
        outline.stroke()

        let inner = track.insetBy(dx: bounds.width * 0.018, dy: bounds.height * 0.018)
        var fill = inner
        if let progress {
            fill.size.width *= progress
        } else {
            fill.size.width *= 0.3
            fill.origin.x += (inner.width - fill.width) * (sin(phase * 3) + 1) / 2
        }
        if fill.width > 0 {
            (paused ? NSColor.systemOrange : NSColor.systemBlue).setFill()
            NSBezierPath(roundedRect: fill, xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
        }
    }
}
