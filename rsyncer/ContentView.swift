import SwiftUI

enum Palette {
    static let green = Color(red: 0.19, green: 0.43, blue: 0.34)
    static let sidebar = Color(red: 0.09, green: 0.15, blue: 0.14)
    static let canvas = Color(nsColor: .windowBackgroundColor)
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var deleteID: UUID?
    @State private var launchID: UUID?
    @State private var draggedPairID: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var dragSlots: [CGRect] = []
    @State private var dragStartY: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @GestureState private var reorderGestureActive = false
    private var showVolumes: Bool { store.showingVolumes }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 238)
            Group {
                if showVolumes {
                    VolumesView(monitor: store.volumes)
                } else if let pair = store.selectedPair {
                    PairDetailView(pairID: pair.id).id(pair.id)
                } else {
                    ContentUnavailableView {
                        Label("Make room for a little order", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Save a pair of locations to start your first sync.")
                    } actions: {
                        Button("Create a sync", action: store.addPair).buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
        }
        .frame(minWidth: 980, minHeight: 720)
        .tint(Palette.green)
        .sheet(isPresented: $showSettings) { AppSettingsView().environmentObject(store) }
        .alert("Rename saved sync", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Sync name", text: $renameText)
            Button("Cancel", role: .cancel) { renameID = nil }
            Button("Rename") {
                if let renameID { store.renamePair(renameID, to: renameText) }
                renameID = nil
            }.disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("Delete this saved sync?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Delete saved sync", role: .destructive) {
                if let deleteID { store.removePair(deleteID) }
                deleteID = nil
            }
        } message: { Text("This removes the saved pair. Files and run logs are kept.") }
        .confirmationDialog("Delete extra destination files?", isPresented: Binding(get: { launchID != nil }, set: { if !$0 { launchID = nil } })) {
            Button("Sync and delete extra files", role: .destructive) {
                if let pair = store.pairs.first(where: { $0.id == launchID }) { launch(pair) }
                launchID = nil
            }
        } message: {
            Text("Files in \(store.pairs.first(where: { $0.id == launchID })?.destination ?? "the destination") that do not exist in the source may be permanently deleted. Run a preview first to review the changes.")
        }
        .alert("rsyncer needs your attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color(red: 0.65, green: 0.85, blue: 0.62))
                Text("rsyncer").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 8)
            Text("A place for everything.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 24).padding(.bottom, 38)
            HStack {
                Text("SAVED SYNCS").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Spacer()
                Button { store.addPair(); store.showingVolumes = false } label: { Image(systemName: "plus").font(.system(size: 13)) }
                    .buttonStyle(.plain).help("New sync pair")
            }.foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 24).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.pairs) { pair in
                        HStack(spacing: 4) {
                            HStack(spacing: 12) {
                                SyncStatusIcon(active: store.activePairID == pair.id, paused: store.isPaused, cancelling: store.cancelling)
                                    .font(.system(size: 17))
                                    .foregroundStyle(store.selectedID == pair.id && !showVolumes ? Color(red: 0.69, green: 0.87, blue: 0.68) : .white.opacity(0.5))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pair.name.isEmpty ? "Untitled sync" : pair.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(store.activePairID == pair.id ? (store.cancelling ? "Stopping…" : store.isPaused ? "Paused" : "In progress") : pair.schedule.kind == .manual ? "On your terms" : pair.schedule.kind.title)
                                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if pair.schedule.kind != .manual { Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { store.selectedID = pair.id; store.showingVolumes = false }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { store.selectedID = pair.id; store.showingVolumes = false }
                            .highPriorityGesture(reorderGesture(for: pair.id))
                            .help("Click to select; drag to reorder")
                            Button { requestLaunch(pair) } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(store.isRunning || !pair.isConfigured ? 0.2 : 0.7))
                                    .frame(width: 28, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isRunning || !pair.isConfigured)
                            .help("Launch sync")
                            .accessibilityLabel("Launch \(pair.name.isEmpty ? "Untitled sync" : pair.name)")
                            .padding(.trailing, 8)
                        }
                        .background(store.selectedID == pair.id && !showVolumes ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") { renameText = pair.name; renameID = pair.id }
                                .disabled(store.activePairID == pair.id)
                            Button("Launch", systemImage: "play.fill") { requestLaunch(pair) }
                                .disabled(store.isRunning || !pair.isConfigured)
                            Button(store.isPaused && store.activePairID == pair.id ? "Resume sync" : "Pause current sync", systemImage: store.isPaused && store.activePairID == pair.id ? "play.fill" : "pause.fill", action: store.togglePause)
                                .disabled(store.activePairID != pair.id || store.cancelling)
                            Divider()
                            Button("Move up", systemImage: "arrow.up") { store.movePair(pair.id, by: -1) }
                                .disabled(store.pairs.first?.id == pair.id)
                            Button("Move down", systemImage: "arrow.down") { store.movePair(pair.id, by: 1) }
                                .disabled(store.pairs.last?.id == pair.id)
                            Divider()
                            Button("Delete…", systemImage: "trash", role: .destructive) { deleteID = pair.id }
                                .disabled(store.activePairID == pair.id)
                        }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: SavedSyncFrames.self, value: [pair.id: geometry.frame(in: .named("savedSyncs"))])
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(draggedPairID == pair.id ? Color.white.opacity(0.4) : .clear)
                                .allowsHitTesting(false)
                        }
                        .offset(y: dragOffset(for: pair.id))
                        .zIndex(draggedPairID == pair.id ? 1 : 0)
                    }
                }.padding(.horizontal, 12)
            }
            .coordinateSpace(name: "savedSyncs")
            .onPreferenceChange(SavedSyncFrames.self) { rowFrames = $0 }
            .onChange(of: reorderGestureActive) { _, active in
                if !active { finishReordering() }
            }
            Spacer(minLength: 20)
            SidebarVolumes(monitor: store.volumes) { store.showingVolumes = true }
            Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 24).padding(.vertical, 20)
            Button { showSettings = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Settings").font(.system(size: 12))
                    Spacer()
                    Text("1.0").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }.foregroundStyle(.white.opacity(0.65))
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .background(Palette.sidebar)
    }

    private func reorderGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("savedSyncs"))
            .updating($reorderGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                if draggedPairID == nil {
                    guard let frame = rowFrames[id], store.pairs.allSatisfy({ rowFrames[$0.id] != nil }) else { return }
                    draggedPairID = id
                    dragSlots = store.pairs.compactMap { rowFrames[$0.id] }
                    dragStartY = frame.midY
                }
                guard draggedPairID == id,
                      let source = store.pairs.firstIndex(where: { $0.id == id }) else { return }
                dragTranslation = value.translation.height
                let destination = SyncReorder.destination(for: dragStartY + dragTranslation, slotCenters: dragSlots.map(\.midY))
                if let destination, destination != source {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        store.movePair(id, by: destination - source)
                    }
                }
            }
            .onEnded { _ in finishReordering() }
    }

    private func dragOffset(for id: UUID) -> CGFloat {
        guard draggedPairID == id, let index = store.pairs.firstIndex(where: { $0.id == id }), dragSlots.indices.contains(index) else { return 0 }
        return dragStartY + dragTranslation - dragSlots[index].midY
    }

    private func finishReordering() {
        withAnimation(.easeOut(duration: 0.16)) {
            draggedPairID = nil
            dragTranslation = 0
            dragSlots = []
        }
    }

    private func requestLaunch(_ pair: SyncPair) {
        if pair.options.deleteExtraneous { launchID = pair.id }
        else { launch(pair) }
    }

    private func launch(_ pair: SyncPair) {
        store.selectedID = pair.id
        store.showingVolumes = false
        store.start(pair, preview: false)
    }
}

struct SyncStatusIcon: View {
    var active: Bool
    var paused: Bool
    var cancelling: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || paused || cancelling || reduceMotion)) { context in
            Image(systemName: active ? (paused ? "pause.circle" : "arrow.triangle.2.circlepath") : "folder")
                .rotationEffect(.degrees(active && !paused && !cancelling && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5 * 360 : 0))
        }
        .accessibilityLabel(active ? (paused ? "Sync paused" : cancelling ? "Sync stopping" : "Sync running") : "Saved sync")
    }
}

struct SidebarVolumes: View {
    @ObservedObject var monitor: VolumeMonitor
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CONNECTED DRIVES").font(.system(size: 10, weight: .semibold)).tracking(1.3)
                Spacer()
                Text("\(monitor.volumes.count)").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.white.opacity(0.45))
            ForEach(monitor.volumes.prefix(4)) { volume in
                Button(action: action) {
                    HStack(spacing: 10) {
                        Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive").font(.system(size: 17))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(volume.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text(volume.status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                        Circle().fill(volume.isLow || volume.isReadOnly ? .orange : Color(red: 0.62, green: 0.81, blue: 0.55)).frame(width: 5, height: 5)
                    }.foregroundStyle(.white.opacity(0.75))
                }.buttonStyle(.plain)
            }
            Button("View all drives", action: action).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
        }.padding(.horizontal, 24)
    }
}

private struct SavedSyncFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
