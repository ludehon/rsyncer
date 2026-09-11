import SwiftUI
import UniformTypeIdentifiers

struct PairDetailView: View {
    @EnvironmentObject private var store: AppStore
    let pairID: UUID
    @State private var tab = DetailTab.options
    @State private var confirmMirror = false
    @State private var hoveringMode = false
    enum DetailTab: String, CaseIterable { case options = "Options", schedule = "Schedule", preview = "Preview", activity = "Activity" }
    private var pair: SyncPair { store.pairs.first { $0.id == pairID } ?? SyncPair() }
    private var locked: Bool { store.activePairID == pairID }
    private var binding: Binding<SyncPair> { Binding(get: { pair }, set: { store.update($0) }) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    HStack(alignment: .center, spacing: 12) {
                        Label(locked ? (store.isPaused ? "Paused" : "Syncing") : pair.direction.title, systemImage: locked ? (store.isPaused ? "pause.circle" : "arrow.triangle.2.circlepath") : pair.direction.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.36, green: 0.72, blue: 0.55))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(Palette.green.opacity(0.14), in: Capsule())
                            .contentShape(Capsule())
                            .onHover { hoveringMode = $0 }
                            .popover(isPresented: $hoveringMode, arrowEdge: .bottom) {
                                Text(pair.direction == .oneWay
                                     ? "Folder contents are copied into the destination. Your source stays intact."
                                     : "Copies both ways; newer files win. Deletions are not shared. Equal-date differences favor the source; use checksums to detect equal-size differences. Preview compares each direction independently.")
                                    .font(.system(size: 11))
                                    .frame(maxWidth: 260, alignment: .leading)
                                    .padding(12)
                            }
                        Spacer()
                    }
                    HStack(spacing: 14) {
                        LocationCard(title: "SOURCE", subtitle: "The files you want to bring along", path: binding.source, source: true, pairID: pairID)
                        LocationCard(title: "DESTINATION", subtitle: "The place they’ll call home", path: binding.destination, source: false, pairID: pairID)
                    }.disabled(locked)
                    VStack(spacing: 0) {
                        HStack(spacing: 16) {
                            DetailTabSelector(selection: $tab, activityCount: store.history.filter { $0.pairID == pairID }.count)
                            Spacer(minLength: 0)
                            if !store.changesSaved {
                                Text("NOT SAVED")
                                    .font(.system(size: 9, weight: .medium)).tracking(1.2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Group {
                            switch tab {
                            case .options: SyncOptionsView(options: binding.options, twoWay: pair.direction == .twoWay).disabled(locked)
                            case .schedule: ScheduleView(pair: binding).disabled(locked)
                            case .activity: ActivityView(pairID: pairID)
                            case .preview: SyncPreviewView(pairID: pairID)
                            }
                        }.padding(.top, 22)
                    }
                }.padding(32)
            }
            footer
        }
        .confirmationDialog("Delete extra destination files?", isPresented: $confirmMirror) {
            Button("Sync and delete extra files", role: .destructive) { store.start(pair, preview: false); tab = .activity }
        } message: { Text("Files in \(pair.destination) that do not exist in the source may be permanently deleted. Run a preview first to review the changes.") }
    }

    private var footer: some View {
        VStack(spacing: 13) {
            if locked {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(store.isPreview ? (pair.direction == .twoWay ? "Comparing files · current direction" : "Comparing files") : "Current file progress").font(.system(size: 11, weight: .medium))
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
                Button(action: store.revealLogs) {
                    Label("View logs", systemImage: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.greenBright)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                Spacer()
                if locked {
                    Button(store.isPaused ? "Resume sync" : "Pause sync", action: store.togglePause).disabled(store.cancelling).controlSize(.large)
                    Button(store.cancelling ? "Stopping…" : "Stop sync", role: .destructive, action: store.cancel).disabled(store.cancelling).controlSize(.large)
                } else {
                    Button { store.start(pair, preview: true); tab = .preview } label: {
                        Label("Preview", systemImage: "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.greenBright)
                            .padding(.horizontal, 18).frame(height: 30)
                            .background(Palette.greenBright.opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Palette.greenBright.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
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
                            .padding(.horizontal, 24).frame(height: 30)
                            .background(Palette.green, in: Capsule())
                            .contentShape(Capsule())
                    }
                        .buttonStyle(.plain)
                        .opacity(!pair.isConfigured || store.isRunning ? 0.4 : 1)
                        .disabled(!pair.isConfigured || store.isRunning)
                }
            }
        }.padding(.horizontal, 32).padding(.vertical, 20).background(.background).overlay(alignment: .top) { Divider() }
    }
}

struct DetailTabSelector: View {
    @Binding var selection: PairDetailView.DetailTab
    let activityCount: Int

    var body: some View {
        Picker("Sync sections", selection: $selection) {
            ForEach(PairDetailView.DetailTab.allCases, id: \.self) { item in
                Text(item == .activity && activityCount > 0
                     ? "Activity (\(activityCount))"
                     : item.rawValue)
                    .tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(maxWidth: 540, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 12) {
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
                        .font(.system(size: 36, weight: .light)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(source ? Palette.green : Color(red: 0.65, green: 0.48, blue: 0.26))
                        .frame(height: 42)
                }.buttonStyle(.plain)
                    .accessibilityLabel(path.isEmpty ? "Choose \(source ? "source" : "destination")" : "Open \(source ? "source" : "destination") in Finder")
                    .help(path.isEmpty ? "Choose a location" : "Open in Finder")
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
