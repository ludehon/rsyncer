import SwiftUI
import AppKit

@main
struct ReorderGestureTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rsyncer-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataDirectory: directory, enableScheduling: false)
        store.pairs = [SyncPair(name: "First"), SyncPair(name: "Second"), SyncPair(name: "Third")]
        store.selectedID = store.pairs[0].id
        let view = ContentView().environmentObject(store).frame(width: 1120, height: 840)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 840), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        // Deliver real AppKit mouse events to this isolated hosting window.
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func mouse(_ type: NSEvent.EventType, _ y: CGFloat) {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 110, y: y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        }
        mouse(.leftMouseDown, 595)
        mouse(.leftMouseUp, 595)
        try expect(store.selectedPair?.name == "Second", "Clicking a card still selects it")
        mouse(.leftMouseDown, 665)
        for y in stride(from: 659.0, through: 530.0, by: -6) { mouse(.leftMouseDragged, y) }
        try expect(store.pairs.map(\.name) == ["Second", "Third", "First"], "Rows reorder downward before mouse release")
        mouse(.leftMouseUp, 530)
        try expect(store.pairs.map(\.name) == ["Second", "Third", "First"], "Releasing keeps the new order")
        mouse(.leftMouseDown, 535)
        for y in stride(from: 541.0, through: 665.0, by: 6) { mouse(.leftMouseDragged, y) }
        try expect(store.pairs.map(\.name) == ["First", "Second", "Third"], "Rows reorder upward before mouse release")
        mouse(.leftMouseUp, 665)
        try expect(store.selectedPair?.name == "Second", "Dragging does not change the selected sync")
        let reloaded = AppStore(dataDirectory: directory, enableScheduling: false)
        try expect(reloaded.pairs.map(\.name) == ["First", "Second", "Third"], "Drag order persists across reload")
        print("All mouse reordering checks passed.")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SyncError.invalid("FAIL: \(message)") }
        print("PASS: \(message)")
    }
}
