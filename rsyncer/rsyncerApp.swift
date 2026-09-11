import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A sync is still running"
        alert.informativeText = "Stop the sync before quitting. Partial files may remain in the destination."
        alert.addButton(withTitle: "Keep syncing")
        alert.addButton(withTitle: "Stop sync")
        if alert.runModal() == .alertSecondButtonReturn { store.cancel() }
        return .terminateCancel
    }
}

@main
struct rsyncerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        Window("rsyncer", id: "main") {
            ContentView().environmentObject(store)
                .onAppear { delegate.store = store; store.tick() }
        }
        .defaultSize(width: 1120, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Menu("New sync pair") {
                    ForEach(SyncDirection.allCases) { direction in
                        Button(direction.title) {
                            store.addPair(direction: direction)
                            store.showingVolumes = false
                        }
                    }
                }
            }
        }
        Settings { AppSettingsView().environmentObject(store) }
        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(systemName: store.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                .accessibilityLabel("rsyncer")
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(store.isRunning ? "\(store.isPaused ? "Paused" : store.isPreview ? "Previewing" : "Syncing") \(store.activePairName)" : "rsyncer · Ready when you are")
        if store.isRunning {
            Text(store.progressDetail)
            Button(store.isPaused ? "Resume sync" : "Pause sync", action: store.togglePause).disabled(store.cancelling)
            Button("Stop sync", action: store.cancel).disabled(store.cancelling)
        }
        Divider()
        Button("Open rsyncer") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut("o")
        if !store.pairs.isEmpty {
            Menu("Saved syncs") {
                ForEach(store.pairs) { pair in
                    Button(pair.name.isEmpty ? "Untitled sync" : pair.name) {
                        store.selectedID = pair.id
                        store.showingVolumes = false
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
        Button("Open logs", action: store.revealLogs)
        Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: store.setLoginEnabled))
        Divider()
        Button("Quit rsyncer") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
