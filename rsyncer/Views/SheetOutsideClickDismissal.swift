import SwiftUI
import AppKit

/// Keeps native sheet keyboard/focus behavior while allowing backdrop dismissal.
struct SheetOutsideClickDismissal: NSViewRepresentable {
    var dismiss: () -> Void

    func makeNSView(context: Context) -> OutsideClickView {
        let view = OutsideClickView()
        view.dismiss = dismiss
        return view
    }

    func updateNSView(_ view: OutsideClickView, context: Context) { view.dismiss = dismiss }

    static func dismantleNSView(_ view: OutsideClickView, coordinator: ()) { view.stopMonitoring() }

    final class OutsideClickView: NSView {
        var dismiss: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let sheet = self.window,
                      Self.isBackdropClick(in: event.window, at: event.locationInWindow, sheet: sheet) else { return event }
                self.dismiss?()
                // Consume the click so the underlying sync controls cannot fire.
                return nil
            }
        }

        static func isBackdropClick(in eventWindow: NSWindow?, at location: NSPoint, sheet: NSWindow) -> Bool {
            guard let parent = sheet.sheetParent, eventWindow === parent else { return false }
            let point = parent.convertPoint(toScreen: location)
            return !sheet.frame.contains(point)
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
