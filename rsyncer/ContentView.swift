import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var deleteID: UUID?
    @State private var launchID: UUID?
    @State private var detailTab = PairDetailView.DetailTab.activity
    @State private var draggedPairID: UUID?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var dragSlots: [CGRect] = []
    @State private var dragStartY: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @GestureState private var reorderGestureActive = false
    private var showVolumes: Bool { store.showingVolumes }
    private var deleteMenuTitle: AttributedString {
        var title = AttributedString("Delete…")
        title.foregroundColor = .red
        return title
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 238)
            Group {
                if showVolumes {
                    VolumesView(monitor: store.volumes)
                } else if let pair = store.selectedPair {
                    PairDetailView(pairID: pair.id, tab: $detailTab).id(pair.id)
                } else {
                    ContentUnavailableView {
                        Label("Make room for a little order", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Save a pair of locations to start your first sync.")
                    } actions: {
                        Menu("Create a sync") { newSyncOptions }.menuStyle(.borderlessButton).fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
        }
        .id(store.theme)
        .frame(minWidth: 980, minHeight: 720)
        .tint(Palette.accent)
        .onChange(of: store.selectedID) { _, selectedID in
            detailTab = .activity
        }
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
        .alert("Source is unavailable", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var newSyncOptions: some View {
        ForEach(SyncDirection.allCases) { direction in
            Button {
                store.addPair(direction: direction)
                store.showingVolumes = false
            } label: {
                Label(direction.title, systemImage: direction.symbol)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark()
                    .fill(Palette.soft, style: FillStyle(eoFill: true))
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("Rsyncer").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 8)
            Spacer().frame(height: 38)
            HStack {
                Text("SAVED SYNCS").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Spacer()
                Menu { newSyncOptions } label: { Image(systemName: "plus").font(.system(size: 13)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Add sync").help("New sync pair")
            }.foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 24).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.pairs) { pair in
                        HStack(spacing: 4) {
                            HStack(spacing: 12) {
                                SyncStatusIcon(active: store.activePairID == pair.id, preview: store.isPreview, paused: store.isPaused, cancelling: store.cancelling)
                                    .font(.system(size: 17))
                                    .foregroundStyle(store.selectedID == pair.id && !showVolumes ? Palette.soft : .white.opacity(0.5))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pair.name.isEmpty ? "Untitled sync" : pair.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(syncStatus(for: pair))
                                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                        .monospacedDigit()
                                        .help(syncStatus(for: pair))
                                }
                                Spacer(minLength: 0)
                                if pair.schedule.kind != .manual { Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { selectSavedPair(pair) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { selectSavedPair(pair) }
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
                            Button(store.isPaused && store.activePairID == pair.id ? (store.isPreview ? "Resume preview" : "Resume sync") : (store.isPreview ? "Pause current preview" : "Pause current sync"), systemImage: store.isPaused && store.activePairID == pair.id ? "play.fill" : "pause.fill", action: store.togglePause)
                                .disabled(store.activePairID != pair.id || store.cancelling)
                            Divider()
                            Button("Move up", systemImage: "arrow.up") { store.movePair(pair.id, by: -1) }
                                .disabled(store.pairs.first?.id == pair.id)
                            Button("Move down", systemImage: "arrow.down") { store.movePair(pair.id, by: 1) }
                                .disabled(store.pairs.last?.id == pair.id)
                            Divider()
                            Button(role: .destructive) { deleteID = pair.id } label: {
                                Label {
                                    Text(deleteMenuTitle)
                                } icon: {
                                    Image(systemName: "trash").foregroundStyle(.red)
                                }
                            }
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
            Button { showSettings = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .medium))
                    Text("Settings").font(.system(size: 12))
                    Spacer()
                }.foregroundStyle(.white.opacity(0.65))
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .background(Palette.sidebar)
    }

    private func syncStatus(for pair: SyncPair) -> String {
        guard store.activePairID == pair.id else {
            return pair.schedule.kind == .manual ? "Manual" : pair.schedule.kind.title
        }
        if store.cancelling { return "Stopping…" }
        if store.isPaused { return "Paused" }
        if let progress = store.progress {
            let percentage = progress.formatted(.percent.precision(.fractionLength(0)))
            return store.isPreview ? "Comparing · \(percentage)" : "\(store.isTransferring ? "Syncing" : "Checking") · \(percentage)"
        }
        return store.progressDetail
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
        if pair.direction == .oneWay && pair.options.deleteExtraneous { launchID = pair.id }
        else { launch(pair) }
    }

    private func launch(_ pair: SyncPair) {
        detailTab = .activity
        store.selectedID = pair.id
        store.showingVolumes = false
        store.start(pair, preview: false)
    }

    private func selectSavedPair(_ pair: SyncPair) {
        detailTab = .activity
        store.selectedID = pair.id
        store.showingVolumes = false
    }
}

struct SyncStatusIcon: View {
    var active: Bool
    var preview: Bool
    var paused: Bool
    var cancelling: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || paused || cancelling || reduceMotion)) { context in
            Image(systemName: active ? (paused ? "pause.circle" : preview ? "eye" : "arrow.triangle.2.circlepath") : "folder")
                .rotationEffect(.degrees(active && !paused && !cancelling && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5 * 360 : 0))
        }
        .accessibilityLabel(active ? (paused ? (preview ? "Preview paused" : "Sync paused") : cancelling ? (preview ? "Preview stopping" : "Sync stopping") : (preview ? "Preview running" : "Sync running")) : "Saved sync")
    }
}

private struct SavedSyncFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
