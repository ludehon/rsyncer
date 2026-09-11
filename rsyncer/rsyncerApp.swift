import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore? {
        didSet {
            guard store !== oldValue else { return }
            dockProgress = store.map { DockProgressController(store: $0) }
        }
    }
    private var dockProgress: DockProgressController?
    private weak var mainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        if let mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(mainWindowCloseObserver)
        }
        mainWindow = window
        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mainWindow = nil
                if self.store?.hideDockIconWhenClosed == true {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func restoreDockIcon() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreDockIcon()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = store.isPreview ? "A preview is still running" : "A sync is still running"
        alert.informativeText = store.isPreview ? "Stop the preview before quitting." : "Stop the sync before quitting. Partial files may remain in the destination."
        alert.addButton(withTitle: store.isPreview ? "Keep previewing" : "Keep syncing")
        alert.addButton(withTitle: store.isPreview ? "Stop preview" : "Stop sync")
        if alert.runModal() == .alertSecondButtonReturn { store.cancel() }
        return .terminateCancel
    }
}

@main
struct rsyncerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        Window("Rsyncer", id: "main") {
            ContentView().environmentObject(store)
                .onAppear { delegate.store = store; store.tick() }
                .background(MainWindowRegistration(register: delegate.registerMainWindow))
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
            MenuBarView(restoreDockIcon: delegate.restoreDockIcon).environmentObject(store)
        } label: {
            Image(systemName: store.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                .accessibilityLabel("Rsyncer")
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    let restoreDockIcon: () -> Void

    private func openMainWindow() {
        restoreDockIcon()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        Text(store.isRunning ? "\(store.isPaused ? "Paused" : store.isPreview ? "Previewing" : "Syncing") \(store.activePairName)" : "rsyncer · Ready when you are")
        if store.isRunning {
            Text(store.progressDetail)
            Button(store.isPaused ? (store.isPreview ? "Resume preview" : "Resume sync") : (store.isPreview ? "Pause preview" : "Pause sync"), action: store.togglePause).disabled(store.cancelling)
            Button(store.isPreview ? "Stop preview" : "Stop sync", action: store.cancel).disabled(store.cancelling)
        }
        Divider()
        Button("Open rsyncer", action: openMainWindow).keyboardShortcut("o")
        if !store.pairs.isEmpty {
            Menu("Saved syncs") {
                ForEach(store.pairs) { pair in
                    Button(pair.name.isEmpty ? "Untitled sync" : pair.name) {
                        store.selectedID = pair.id
                        store.showingVolumes = false
                        openMainWindow()
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

private struct MainWindowRegistration: NSViewRepresentable {
    let register: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { register(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { register(window) }
        }
    }
}
