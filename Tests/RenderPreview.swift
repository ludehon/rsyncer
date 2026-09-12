import SwiftUI
import AppKit

@main
struct RenderPreview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rsyncer-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(dataDirectory: directory, enableScheduling: false)
        let visualPreview = CommandLine.arguments.contains("--sync-preview")
        let pair = SyncPair(name: "Photo backup", source: "/Users/lucien/Pictures", destination: "/Volumes/Archive/Photos")
        store.pairs = [pair, SyncPair(name: "Project archive"), SyncPair(name: "Documents")]
        store.selectedID = pair.id
        let now = Date()
        store.history = (0..<6).map { index in
            RunRecord(pairID: pair.id, pairName: pair.name,
                      startedAt: now.addingTimeInterval(Double(-index * 3600 - 12)),
                      finishedAt: now.addingTimeInterval(Double(-index * 3600)),
                      preview: index % 3 != 1, exitCode: index == 4 ? 20 : 0,
                      cancelled: index == 4, logPath: "/tmp/rsyncer-preview.log")
        }
        if visualPreview {
            store.syncPreview = SyncPreview(pair: pair, changes: SyncPreview.parse("RSYNCER2|cd+++++++|4096|Summer 2026/\nRSYNCER2|>f+++++++|8400000|Summer 2026/Coast.jpg\nRSYNCER2|>f+++++++|6200000|Summer 2026/Sunset.jpg\nRSYNCER2|>f.s.......|4200000|Favorites.jpg\n*deleting Old export.jpg\n", pair: pair), complete: true, succeeded: true)
        }
        let content = visualPreview
            ? AnyView(ScrollView { SyncPreviewView(pairID: pair.id).padding(32) })
            : AnyView(ContentView())
        let view = content.background(Color(nsColor: .windowBackgroundColor)).environmentObject(store).frame(width: 1120, height: 840)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 840), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Could not render") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let url = URL(fileURLWithPath: "/tmp/rsyncer-preview.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        print(url.path)
    }
}
