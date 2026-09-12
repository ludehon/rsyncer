import SwiftUI
import UniformTypeIdentifiers

struct PairDetailView: View {
    @EnvironmentObject private var store: AppStore
    let pairID: UUID
    @Binding var tab: DetailTab
    @State private var confirmMirror = false
    @State private var hoveringMode = false
    enum DetailTab: String, CaseIterable { case activity = "Activity", preview = "Preview", schedule = "Schedule", options = "Options" }
    private var pair: SyncPair { store.pairs.first { $0.id == pairID } ?? SyncPair() }
    private var locked: Bool { store.activePairID == pairID }
    private var binding: Binding<SyncPair> { Binding(get: { pair }, set: { store.update($0) }) }

    var body: some View {
        VStack(spacing: 0) {
            // The header stays put; only the selected tab’s contents scroll.
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SYNC WORKSPACE")
                            .font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary)
                        Text(pair.name.isEmpty ? "Untitled sync" : pair.name)
                            .font(.system(size: 26, weight: .semibold)).tracking(-0.7).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Label(locked ? (store.isPaused ? "Paused" : store.isPreview ? "Previewing" : "Syncing") : pair.direction.title, systemImage: locked ? (store.isPaused ? "pause.circle" : store.isPreview ? "eye" : "arrow.triangle.2.circlepath") : pair.direction.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.accentInk)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Palette.accent.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                        .onHover { hoveringMode = $0 }
                        .popover(isPresented: $hoveringMode, arrowEdge: .bottom) {
                            Text(pair.direction == .oneWay
                                 ? "Folder contents are copied into the destination"
                                 : "Copies both ways, newer files win. Deletions are not shared. Equal-date differences favor the source; use checksums to detect equal-size differences. Preview compares each direction independently.")
                                .font(.system(size: 11))
                                .frame(maxWidth: 260, alignment: .leading)
                                .padding(12)
                        }
                }
                HStack(spacing: 12) {
                    LocationCard(
                        title: pair.direction == .twoWay ? "SOURCE 1" : "SOURCE",
                        subtitle: pair.direction == .twoWay ? "The first location to keep in sync" : "The files you want to bring along",
                        path: binding.source,
                        source: true,
                        locationName: pair.direction == .twoWay ? "Source 1" : "Source",
                        pairID: pairID
                    )
                    Image(systemName: pair.direction.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.accentInk)
                        .frame(width: 30, height: 30)
                        .background(Palette.accent.opacity(0.08), in: Circle())
                        .accessibilityLabel(pair.direction.title)
                    LocationCard(
                        title: pair.direction == .twoWay ? "SOURCE 2" : "DESTINATION",
                        subtitle: pair.direction == .twoWay ? "The second location to keep in sync" : "The place they’ll call home",
                        path: binding.destination,
                        source: false,
                        locationName: pair.direction == .twoWay ? "Source 2" : "Destination",
                        pairID: pairID
                    )
                }.disabled(locked)
                HStack(spacing: 16) {
                    DetailTabSelector(selection: $tab, activityCount: store.history.filter { $0.pairID == pairID }.count)
                    if !store.changesSaved {
                        Text("NOT SAVED")
                            .font(.system(size: 9, weight: .medium)).tracking(1.2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 0)
            ScrollView {
                Group {
                    switch tab {
                    case .options: SyncOptionsView(options: binding.options, twoWay: pair.direction == .twoWay).disabled(locked)
                    case .schedule: ScheduleView(pair: binding).disabled(locked)
                    case .activity: ActivityView(pairID: pairID)
                    case .preview: SyncPreviewView(pairID: pairID)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .onAppear {
            if locked { tab = .activity }
        }
        .confirmationDialog("Delete extra destination files?", isPresented: $confirmMirror) {
            Button("Sync and delete extra files", role: .destructive) { store.start(pair, preview: false); tab = .activity }
        } message: { Text("Files in \(pair.destination) that do not exist in the source may be permanently deleted. Run a preview first to review the changes.") }
    }

    private var footer: some View {
        VStack(spacing: 13) {
            if locked && tab != .activity {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(store.isPreview ? (pair.direction == .twoWay ? "Comparing files · current direction" : "Comparing files") : store.isTransferring ? "Syncing files" : "Checking files").font(.system(size: 11, weight: .medium))
                        Spacer()
                        if let progress = store.progress { Text(progress, format: .percent.precision(.fractionLength(0))).font(.system(size: 11, design: .monospaced)) }
                    }
                    if let progress = store.progress { ProgressView(value: progress) }
                    else if store.isPaused { ProgressView(value: 0) }
                    else { ProgressView().progressViewStyle(.linear) }
                    Text(store.isPaused ? "Paused — resume to continue this transfer." : store.progressDetail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack {
                Label(locked ? "Run in progress" : "Preview changes before you sync", systemImage: locked ? "waveform.path" : "eye")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if locked {
                    Button(action: store.togglePause) {
                        Label(store.isPaused ? (store.isPreview ? "Resume preview" : "Resume sync") : (store.isPreview ? "Pause preview" : "Pause sync"), systemImage: store.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accentInk)
                            .padding(.horizontal, 18).frame(height: 36)
                            .background(Palette.accentBright.opacity(0.12), in: Capsule())
                            .overlay { Capsule().strokeBorder(Palette.accentBright.opacity(0.85), lineWidth: 1) }
                            .contentShape(Capsule())
                    }
                        .buttonStyle(.plain)
                        .opacity(store.cancelling ? 0.4 : 1)
                        .disabled(store.cancelling)
                    Button(action: store.cancel) {
                        Label(store.cancelling ? "Stopping…" : (store.isPreview ? "Stop preview" : "Stop sync"), systemImage: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).frame(height: 36)
                            .background(Color.red, in: Capsule())
                            .contentShape(Capsule())
                    }
                        .buttonStyle(.plain)
                        .opacity(store.cancelling ? 0.4 : 1)
                        .disabled(store.cancelling)
                } else {
                    Button { store.start(pair, preview: true); tab = .preview } label: {
                        Label("Preview", systemImage: "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accentInk)
                            .padding(.horizontal, 18).frame(height: 36)
                            .background(Palette.accentBright.opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Palette.accent.opacity(0.2), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                    }
                        .buttonStyle(.plain)
                        .opacity(!pair.isConfigured || store.isRunning ? 0.4 : 1)
                        .disabled(!pair.isConfigured || store.isRunning)
                    Button {
                        if pair.direction == .oneWay && pair.options.deleteExtraneous { confirmMirror = true }
                        else { store.start(pair, preview: false); tab = .activity }
                    } label: {
                        Label("Sync now", systemImage: pair.direction.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24).frame(height: 36)
                            .background(Palette.accent, in: Capsule())
                            .contentShape(Capsule())
                    }
                        .buttonStyle(.plain)
                        .opacity(!pair.isConfigured || store.isRunning ? 0.4 : 1)
                        .disabled(!pair.isConfigured || store.isRunning)
                }
            }
        }.padding(.horizontal, 32).padding(.vertical, 16).background(Palette.cardFill).overlay(alignment: .top) { Divider() }
    }
}

struct DetailTabSelector: View {
    @Binding var selection: PairDetailView.DetailTab
    let activityCount: Int

    var body: some View {
        HStack(spacing: 24) {
            ForEach(PairDetailView.DetailTab.allCases, id: \.self) { item in
                Button { selection = item } label: {
                    HStack(spacing: 6) {
                        Text(item.rawValue).font(.system(size: 12, weight: selection == item ? .semibold : .medium))
                        if item == .activity && activityCount > 0 {
                            Text(activityCount.formatted())
                                .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Palette.insetFill, in: Capsule())
                        }
                    }
                    .foregroundStyle(selection == item ? Palette.accentInk : .secondary)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if selection == item {
                            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                .fill(Palette.accent).frame(height: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.cardStroke).frame(height: 1) }
    }
}

struct LocationCard: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var subtitle: String
    @Binding var path: String
    var source: Bool
    var locationName: String
    var pairID: UUID
    @State private var targeted = false
    @State private var hovering = false
    @FocusState private var pathIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: source ? "arrow.up.right" : "arrow.down.right").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    Button {
                        if path.isEmpty {
                            store.chooseLocation(source: source, pairID: pairID)
                        } else {
                            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == false {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } else if !NSWorkspace.shared.open(url) {
                                store.errorMessage = "Could not open \(path) in Finder."
                            }
                        }
                    } label: {
                        Image(systemName: source ? "folder.fill" : "externaldrive.fill")
                            .font(.system(size: 25, weight: .regular)).symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Palette.accentInk)
                            .frame(width: 48, height: 48)
                            .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(path.isEmpty ? "Choose \(locationName)" : "Open \(locationName) in Finder")
                    .help(path.isEmpty ? "Choose a location" : "Open in Finder")
                    if !path.isEmpty && hovering {
                        Button { path = "" } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Color.black.opacity(0.78), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear \(locationName)")
                        .help("Clear \(locationName)")
                        .offset(x: -5, y: -3)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                Button { store.chooseLocation(source: source, pairID: pairID) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(path.isEmpty ? (source ? "Drop a file or folder" : "Drop a folder here") : URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if path.isEmpty {
                            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help("Choose a location")
            }
            HStack(spacing: 5) {
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                TextField("Or type an absolute path…", text: $path).textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced)).lineLimit(1)
                    .focused($pathIsFocused)
                    .accessibilityLabel("\(locationName) path")
            }.padding(9).background(Palette.insetFill, in: RoundedRectangle(cornerRadius: 5))
            if !path.isEmpty {
                LocationStorageView(monitor: store.volumes, path: path)
                    .frame(height: 32, alignment: .bottomLeading)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 16, fill: targeted ? Palette.accent.opacity(0.08) : Palette.cardFill,
                     stroke: targeted ? Palette.accent : Palette.cardStroke, dash: path.isEmpty ? [5, 4] : [])
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onAppear {
            DispatchQueue.main.async { pathIsFocused = false }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, urls.count == 1, url.isFileURL else { return false }
            if !source {
                let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard directory else { store.errorMessage = "Drop a folder or volume into the destination."; return false }
            }
            store.setLocation(url, source: source, pairID: pairID)
            return true
        } isTargeted: { targeted = $0 }
    }
}

struct LocationStorageView: View {
    @ObservedObject var monitor: VolumeMonitor
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let volume = monitor.volume(for: path) {
                if volume.total > 0 {
                    ProgressView(value: volume.usedFraction)
                        .tint(volume.isLow ? .orange : Palette.accent)
                        .accessibilityLabel("\(volume.name) storage used")
                        .accessibilityValue(volume.usedFraction.formatted(.percent.precision(.fractionLength(0))))
                }
                Text(volume.capacityLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Label("Volume unavailable", systemImage: "externaldrive.badge.questionmark")
                    .font(.system(size: 10)).foregroundStyle(.red)
            }
        }
    }
}
