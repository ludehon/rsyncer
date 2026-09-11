import SwiftUI

struct SyncPreviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    let pairID: UUID
    @State private var filter: PreviewChange.Kind?
    @State private var search = ""
    @State private var showingDetails = false
    @State private var targetFilter: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let preview = store.syncPreview, preview.pair.id == pairID {
                VStack(spacing: 10) {
                    transferCard(preview, from: preview.pair.source, to: preview.pair.destination)
                    if preview.pair.direction == .twoWay {
                        transferCard(preview, from: preview.pair.destination, to: preview.pair.source)
                    }
                }.frame(maxWidth: 820)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !preview.complete {
                    status("Comparing your locations…", detail: "The file plan will appear when the comparison finishes.", icon: "magnifyingglass")
                } else {
                    if !preview.succeeded {
                        Label("Comparison incomplete. These are partial results; check Activity for details and run Preview again.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    if let current = store.pairs.first(where: { $0.id == pairID }),
                       current.source != preview.pair.source || current.destination != preview.pair.destination || current.options != preview.pair.options {
                        Label("Settings changed. Run Preview again to refresh this plan.", systemImage: "arrow.clockwise")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    HStack(spacing: 10) {
                        ForEach(PreviewChange.Kind.allCases, id: \.self) { kind in
                            let changes = preview.changes.filter { $0.kind == kind }
                            let metrics = PreviewMetrics(changes)
                            Button { openDetails(kind: kind) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label(kind.rawValue, systemImage: symbol(kind))
                                            .font(.system(size: 12, weight: .semibold))
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                    }
                                    Text(changes.count.formatted()).font(.system(size: 22, weight: .semibold))
                                    Text(metrics.countLabel).font(.system(size: 10))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(metrics.sizeLabel).font(.system(size: 13, weight: .medium))
                                }.foregroundStyle(cardTextColor(kind)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .cardSurface(radius: 10, fill: color(kind).opacity(colorScheme == .dark ? 0.14 : 0.09),
                                                 stroke: color(kind).opacity(colorScheme == .dark ? 0.3 : 0.22))
                            }.buttonStyle(.plain).help("View \(kind.rawValue.lowercased()) items")
                        }
                    }.frame(maxWidth: 820)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if preview.changes.isEmpty && preview.succeeded {
                        status("No file changes needed", detail: "These locations match under your current sync options.", icon: "checkmark.circle")
                    } else if !preview.changes.isEmpty {
                        destinationSummary(preview)
                    }
                    Text("Sizes describe affected file contents, not transfer bytes or space saved. Folder and link sizes are excluded. Unavailable sizes are marked; updates can include metadata only.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if preview.pair.direction == .twoWay {
                    Text("Both directions are compared independently. Each group shows the location that would receive the changes; newer files win during sync.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if preview.pair.options.extendedAttributes {
                    Text("Extended attributes and resource forks are copied during sync but are not compared here.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                status("A clear view before you sync", detail: "Choose Preview below to see additions, updates, and deletions at each destination.", icon: "eye")
            }
        }
        .sheet(isPresented: $showingDetails) {
            if let preview = store.syncPreview, preview.pair.id == pairID {
                details(preview)
                    .background(SheetOutsideClickDismissal { showingDetails = false })
            }
        }
        .onChange(of: store.syncPreview?.complete) { _, complete in
            if complete == false { showingDetails = false }
        }
    }

    private func openDetails(kind: PreviewChange.Kind? = nil, target: String? = nil) {
        filter = kind
        targetFilter = target
        search = ""
        showingDetails = true
    }

    private func destinationSummary(_ preview: SyncPreview) -> some View {
        let groups = Dictionary(grouping: preview.changes, by: \.targetRoot)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WHERE CHANGES WILL HAPPEN").font(.system(size: 9, weight: .semibold)).tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("View all details") { openDetails() }.font(.system(size: 11))
            }
            ForEach(groups.keys.sorted(), id: \.self) { target in
                let changes = groups[target] ?? []
                let metrics = PreviewMetrics(changes)
                Button { openDetails(target: target) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "externaldrive.fill").font(.system(size: 28)).foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(URL(fileURLWithPath: target).lastPathComponent).font(.system(size: 14, weight: .semibold))
                            Text(target).font(.system(size: 10)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(metrics.countLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                            GeometryReader { geometry in
                                HStack(spacing: 2) {
                                    ForEach(PreviewChange.Kind.allCases, id: \.self) { kind in
                                        let count = changes.filter { $0.kind == kind }.count
                                        if count > 0 {
                                            Rectangle().fill(color(kind))
                                                .frame(width: max(0, geometry.size.width - 4) * Double(count) / Double(changes.count))
                                        }
                                    }
                                }.clipShape(Capsule())
                            }.frame(height: 5).accessibilityHidden(true)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 7) {
                            Text(metrics.sizeLabel).font(.system(size: 16, weight: .semibold))
                            Text("View details →").font(.system(size: 10)).foregroundStyle(Palette.accent)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .cardSurface(radius: 10)
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: 820)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ preview: SyncPreview) -> some View {
        let visible = preview.changes.filter {
            (filter == nil || $0.kind == filter) && (targetFilter == nil || $0.targetRoot == targetFilter) &&
            (search.isEmpty || $0.targetPath.localizedCaseInsensitiveContains(search))
        }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preview details").font(.system(size: 20, weight: .semibold))
                    Text("\(visible.count.formatted()) items · \(PreviewMetrics(visible).sizeLabel)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { showingDetails = false }.keyboardShortcut(.cancelAction)
            }
            if let targetFilter { Text(targetFilter).font(.system(size: 11)).textSelection(.enabled) }
            HStack {
                TextField("Find a file or folder…", text: $search).textFieldStyle(.roundedBorder)
                Picker("Changes", selection: $filter) {
                    Text("All changes").tag(Optional<PreviewChange.Kind>.none)
                    ForEach(PreviewChange.Kind.allCases, id: \.self) { kind in
                        Text(kind.rawValue).tag(Optional(kind))
                    }
                }.labelsHidden().frame(width: 140)
            }
            // A bounded native list reuses rows for previews with thousands of files.
            List(visible) { change in
                HStack(spacing: 12) {
                    Image(systemName: change.isDirectory ? "folder.fill" : change.isLink ? "link" : "doc.fill")
                        .font(.system(size: 22)).foregroundStyle(color(change.kind)).frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(change.name).font(.system(size: 12, weight: .medium))
                        Text(change.targetPath).font(.system(size: 10)).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(2).help(change.targetPath)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Label(change.kind.rawValue, systemImage: symbol(change.kind))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(color(change.kind))
                        if !change.isDirectory && !change.isLink {
                            Text(change.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Size unavailable")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.vertical, 7)
            }.listStyle(.inset)
                .overlay { if visible.isEmpty { Text("No changes match this filter.").foregroundStyle(.secondary) } }
        }.padding(24).frame(width: 720, height: 540)
    }

    private func transferCard(_ preview: SyncPreview, from source: String, to destination: String) -> some View {
        let target = RsyncCommand.url(for: destination).path
        let changes = preview.changes.filter { $0.targetRoot == target && $0.kind != .deleted }
        let metrics = PreviewMetrics(changes)
        return HStack(spacing: 18) {
            endpoint(source, title: "FROM", destination: false)
            VStack(spacing: 7) {
                Text(preview.complete ? metrics.sizeLabel : "Comparing…")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.accentBright)
                    .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    Circle().fill(Palette.accentBright.opacity(0.5)).frame(width: 6, height: 6)
                    Capsule().fill(LinearGradient(colors: [Palette.accentBright.opacity(0.45), Palette.accentBright],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(height: 3)
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 13)).foregroundStyle(Palette.accentBright).offset(x: -1)
                }.frame(maxWidth: .infinity).frame(height: 16)
                    .shadow(color: Palette.accentBright.opacity(0.45), radius: 5)
                    .accessibilityLabel("To")
                Text(preview.complete ? (preview.succeeded ? "Planned file contents" : "Partial file contents") : "Calculating size")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.frame(width: 125, alignment: .center)
                .help("Size of added and updated files in this direction. Excludes deletions, folders and links; actual transferred bytes may differ.")
            endpoint(destination, title: "TO", destination: true)
        }
        .padding(18)
        .cardSurface(radius: 15)
    }

    private func endpoint(_ path: String, title: String, destination: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: destination ? "externaldrive.fill" : "folder.fill")
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(destination ? Palette.accent : Color.blue)
                .frame(width: 46, height: 46)
                .background((destination ? Palette.accent : Color.blue).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: destination ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(destination ? Palette.accent : Color.blue)
                        .background(.background, in: Circle()).offset(x: 3, y: 3)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 8, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1).help(path)
                Text(path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: destination ? .trailing : .leading)
    }

    private func status(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private func color(_ kind: PreviewChange.Kind) -> Color {
        switch kind { case .added: Palette.accent; case .updated: .blue; case .deleted: .red }
    }

    private func cardTextColor(_ kind: PreviewChange.Kind) -> Color {
        guard colorScheme == .dark else { return color(kind) }
        switch kind {
        case .added: return Color(red: 0.38, green: 0.86, blue: 0.67)
        case .updated: return Color(red: 0.32, green: 0.72, blue: 1)
        case .deleted: return Color(red: 1, green: 0.42, blue: 0.44)
        }
    }

    private func symbol(_ kind: PreviewChange.Kind) -> String {
        switch kind { case .added: "plus.circle.fill"; case .updated: "arrow.triangle.2.circlepath"; case .deleted: "minus.circle.fill" }
    }
}
