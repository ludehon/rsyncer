import SwiftUI
import UniformTypeIdentifiers

struct PairDetailView: View {
    @EnvironmentObject private var store: AppStore
    let pairID: UUID
    @Binding var tab: DetailTab
    @State private var confirmMirror = false
    @State private var hoveringMode = false
    enum DetailTab: String, CaseIterable { case options = "Options", schedule = "Schedule", preview = "Preview", activity = "Activity" }
    private var pair: SyncPair { store.pairs.first { $0.id == pairID } ?? SyncPair() }
    private var locked: Bool { store.activePairID == pairID }
    private var binding: Binding<SyncPair> { Binding(get: { pair }, set: { store.update($0) }) }

    var body: some View {
        VStack(spacing: 0) {
            // The header stays put; only the selected tab’s contents scroll.
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .center, spacing: 12) {
                    Label(locked ? (store.isPaused ? "Paused" : store.isPreview ? "Previewing" : "Syncing") : pair.direction.title, systemImage: locked ? (store.isPaused ? "pause.circle" : store.isPreview ? "eye" : "arrow.triangle.2.circlepath") : pair.direction.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Palette.accent.opacity(0.14), in: Capsule())
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
                HStack(spacing: 16) {
                    DetailTabSelector(selection: $tab, activityCount: store.history.filter { $0.pairID == pairID }.count)
                    Spacer(minLength: 0)
                    if !store.changesSaved {
                        Text("NOT SAVED")
                            .font(.system(size: 9, weight: .medium)).tracking(1.2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Keep the scroll viewport clear of the segmented control. AppKit draws
            // the control a little outside its SwiftUI layout bounds, so placing a
            // clipping ScrollView directly against it trims the bottom edge.
            .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 10)
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
                // Together with the fixed header inset this preserves the original
                // 22-point gap before the first item without clipping the tab bar.
                .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 32)
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
                Button(action: store.revealLogs) {
                    Label("View logs", systemImage: "doc.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.accentBright)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                Spacer()
                if locked {
                    Button(action: store.togglePause) {
                        Label(store.isPaused ? (store.isPreview ? "Resume preview" : "Resume sync") : (store.isPreview ? "Pause preview" : "Pause sync"), systemImage: store.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.accentBright)
                            .padding(.horizontal, 18).frame(height: 30)
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
                            .padding(.horizontal, 18).frame(height: 30)
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
                            .foregroundStyle(Palette.accentBright)
                            .padding(.horizontal, 18).frame(height: 30)
                            .background(Palette.accentBright.opacity(0.12), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Palette.accentBright.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
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
                            .background(Palette.accent, in: Capsule())
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
                        .foregroundStyle(source ? Palette.accent : Color(red: 0.65, green: 0.48, blue: 0.26))
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
            }.padding(9).background(Palette.insetFill, in: RoundedRectangle(cornerRadius: 5))
            if !path.isEmpty { LocationStorageView(monitor: store.volumes, path: path) }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 13, fill: targeted ? Palette.accent.opacity(0.08) : Palette.cardFill,
                     stroke: targeted ? Palette.accent : Palette.cardStroke, dash: path.isEmpty ? [5, 4] : [])
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
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
