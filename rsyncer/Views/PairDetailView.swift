import SwiftUI
import UniformTypeIdentifiers

struct PairDetailView: View {
    @EnvironmentObject private var store: AppStore
    let pairID: UUID
    @State private var tab = DetailTab.options
    @State private var confirmDelete = false
    @State private var confirmMirror = false
    enum DetailTab: String, CaseIterable { case options = "Options", schedule = "Schedule", activity = "Activity" }
    private var pair: SyncPair { store.pairs.first { $0.id == pairID } ?? SyncPair() }
    private var locked: Bool { store.activePairID == pairID }
    private var binding: Binding<SyncPair> { Binding(get: { pair }, set: { store.update($0) }) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your files. In sync.").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.8)
                            Text("From one location to another. Just the way you want.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(locked ? (store.isPaused ? "Paused" : "Syncing") : "One-way sync", systemImage: locked ? (store.isPaused ? "pause.circle" : "arrow.triangle.2.circlepath") : "arrow.right")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.green)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Palette.green.opacity(0.08), in: Capsule())
                    }
                    HStack(spacing: 14) {
                        LocationCard(title: "SOURCE", subtitle: "The files you want to bring along", path: binding.source, source: true, pairID: pairID)
                        Button {
                            var swapped = pair
                            swap(&swapped.source, &swapped.destination)
                            swap(&swapped.sourceVolumeID, &swapped.destinationVolumeID)
                            store.update(swapped)
                        } label: {
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 16)).foregroundStyle(.secondary)
                                .frame(width: 32, height: 36)
                        }.buttonStyle(.plain).help("Swap source and destination")
                        LocationCard(title: "DESTINATION", subtitle: "The place they’ll call home", path: binding.destination, source: false, pairID: pairID)
                    }.disabled(locked)
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("Folder contents are copied into the destination. Your source stays intact.")
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        HStack(spacing: 27) {
                            ForEach(DetailTab.allCases, id: \.self) { item in
                                Button { tab = item } label: {
                                    VStack(spacing: 13) {
                                        HStack(spacing: 6) {
                                            Text(item.rawValue)
                                            if item == .activity {
                                                Text("\(store.history.filter { $0.pairID == pairID }.count)")
                                                    .font(.system(size: 9)).padding(.horizontal, 5).padding(.vertical, 2)
                                                    .background(.primary.opacity(0.06), in: Capsule())
                                            }
                                        }.font(.system(size: 12, weight: tab == item ? .semibold : .regular))
                                        Rectangle().fill(tab == item ? Palette.green : .clear).frame(height: 2)
                                    }.foregroundStyle(tab == item ? Palette.green : .secondary)
                                }.buttonStyle(.plain)
                            }
                            Spacer()
                            Text(store.changesSaved ? "AUTOSAVED" : "NOT SAVED").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(store.changesSaved ? Color.secondary : .orange).padding(.bottom, 13)
                        }
                        Divider()
                        Group {
                            switch tab {
                            case .options: SyncOptionsView(options: binding.options).disabled(locked)
                            case .schedule: ScheduleView(pair: binding).disabled(locked)
                            case .activity: ActivityView(pairID: pairID)
                            }
                        }.padding(.top, 22)
                    }
                }.padding(32)
            }
            footer
        }
        .confirmationDialog("Delete this saved sync?", isPresented: $confirmDelete) {
            Button("Delete saved sync", role: .destructive) { store.removePair(pairID) }
        } message: { Text("This removes the saved pair. Files and run logs are kept.") }
        .confirmationDialog("Delete extra destination files?", isPresented: $confirmMirror) {
            Button("Sync and delete extra files", role: .destructive) { store.start(pair, preview: false); tab = .activity }
        } message: { Text("Files in \(pair.destination) that do not exist in the source may be permanently deleted. Run a preview first to review the changes.") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            TextField("Sync name", text: binding.name).textFieldStyle(.plain).font(.system(size: 13, weight: .medium)).disabled(locked)
            Spacer()
            if let last = pair.lastRun { Text("Last run \(last.formatted(.relative(presentation: .named)))").font(.system(size: 11)).foregroundStyle(.secondary) }
            Menu {
                Button("Open log folder", action: store.revealLogs)
                Button("Delete saved sync…", role: .destructive) { confirmDelete = true }.disabled(locked)
            } label: { Image(systemName: "ellipsis").frame(width: 22) }.menuStyle(.borderlessButton).fixedSize()
        }.padding(.horizontal, 32).padding(.vertical, 20)
            .overlay(alignment: .bottom) { Divider() }
    }

    private var footer: some View {
        VStack(spacing: 13) {
            if locked {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(store.isPreview ? "Comparing files" : "Current file progress").font(.system(size: 11, weight: .medium))
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
                VStack(alignment: .leading, spacing: 4) {
                    Label(locked ? (store.isPaused ? "Sync paused" : store.isPreview ? "Previewing changes" : "Sync in progress") : pair.isConfigured ? "Ready when you are" : "Choose your locations", systemImage: locked ? (store.isPaused ? "pause.circle" : "arrow.triangle.2.circlepath") : "checkmark.circle")
                        .font(.system(size: 12, weight: .medium))
                    Text(locked ? "You can close this window. rsyncer stays in the menu bar." : "Preview a sync to see what will change.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if locked {
                    Button(store.isPaused ? "Resume sync" : "Pause sync", action: store.togglePause).disabled(store.cancelling).controlSize(.large)
                    Button(store.cancelling ? "Stopping…" : "Stop sync", role: .destructive, action: store.cancel).disabled(store.cancelling).controlSize(.large)
                } else {
                    Button { store.start(pair, preview: true); tab = .activity } label: { Label("Preview", systemImage: "eye").padding(.horizontal, 6) }
                        .controlSize(.large).disabled(!pair.isConfigured || store.isRunning)
                    Button {
                        if pair.options.deleteExtraneous { confirmMirror = true }
                        else { store.start(pair, preview: false); tab = .activity }
                    } label: { Label("Sync now", systemImage: "arrow.right").padding(.horizontal, 12) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!pair.isConfigured || store.isRunning)
                }
            }
        }.padding(.horizontal, 32).padding(.vertical, 20).background(.background).overlay(alignment: .top) { Divider() }
    }
}

struct LocationCard: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var subtitle: String
    @Binding var path: String
    var source: Bool
    var pairID: UUID
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: source ? "arrow.up.right" : "arrow.down.right").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            Button { store.chooseLocation(source: source, pairID: pairID) } label: {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: source ? "folder.fill" : "externaldrive.fill")
                        .font(.system(size: 36, weight: .light)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(source ? Palette.green : Color(red: 0.65, green: 0.48, blue: 0.26))
                        .frame(height: 42)
                    Text(path.isEmpty ? (source ? "Drop a file or folder" : "Drop a folder here") : URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(path.isEmpty ? subtitle : "Click to choose another location")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(spacing: 5) {
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                TextField("Or type an absolute path…", text: $path).textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced)).lineLimit(1)
                    .accessibilityLabel(source ? "Source path" : "Destination path")
            }.padding(9).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
            if !path.isEmpty { LocationStorageView(monitor: store.volumes, path: path) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(targeted ? Palette.green.opacity(0.08) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(targeted ? Palette.green : Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: path.isEmpty ? [5, 4] : [])) }
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
                HStack {
                    Text(volume.name).lineLimit(1)
                    Spacer()
                    if volume.total > 0 {
                        Text("\(volume.usedFraction.formatted(.percent.precision(.fractionLength(0)))) used")
                            .monospacedDigit().fixedSize()
                    }
                }.font(.system(size: 10, weight: .medium))
                if volume.total > 0 {
                    ProgressView(value: volume.usedFraction)
                        .tint(volume.isLow ? .orange : Palette.green)
                        .accessibilityLabel("\(volume.name) storage used")
                        .accessibilityValue(volume.usedFraction.formatted(.percent.precision(.fractionLength(0))))
                }
                Text(volume.capacityLabel).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Label("Volume unavailable", systemImage: "externaldrive.badge.questionmark")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
