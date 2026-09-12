import SwiftUI

struct SyncPreviewView: View {
    private enum ChangeLayout { case list, grid }
    private enum ChangeSort { case name, kind, size, type }

    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    let pairID: UUID
    @State private var search = ""
    @State private var conflictsExpanded = false
    @State private var changeLayout = ChangeLayout.list
    @State private var changeSort = ChangeSort.name
    @State private var sortAscending = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let preview = store.syncPreview, preview.pair.id == pairID {
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
                    if !preview.conflicts.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("\(preview.conflicts.count) two-way \(preview.conflicts.count == 1 ? "conflict" : "conflicts") detected", systemImage: "arrow.triangle.branch")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                            Text("\(preview.pair.options.conflictPolicy.title) will be applied during sync. " + preview.conflicts.prefix(3).map(\.relativePath).joined(separator: " · "))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
                            Menu {
                                ForEach(ConflictPolicy.allCases) { policy in
                                    Button {
                                        store.setConflictPolicy(policy, for: pairID)
                                    } label: {
                                        if preview.pair.options.conflictPolicy == policy {
                                            Label(policy.title, systemImage: "checkmark")
                                        } else { Text(policy.title) }
                                    }
                                }
                            } label: {
                                Label("Resolve: \(preview.pair.options.conflictPolicy.title)", systemImage: "slider.horizontal.3")
                            }
                            .menuStyle(.borderlessButton).fixedSize()
                            DisclosureGroup("Review conflicting files", isExpanded: $conflictsExpanded) {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(preview.conflicts.prefix(250)) { conflict in
                                        Text(conflict.relativePath).font(.system(size: 10, design: .monospaced))
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    if preview.conflicts.count > 250 {
                                        Text("Showing 250 of \(preview.conflicts.count.formatted()) conflicts")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }.padding(.top, 7)
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .padding(12).frame(maxWidth: 820, alignment: .leading)
                        .cardSurface(radius: 10, fill: Color.orange.opacity(0.08), stroke: Color.orange.opacity(0.25))
                    }
                    summaryCards(preview)
                    if preview.changes.isEmpty && preview.succeeded {
                        status("No file changes needed", detail: "These locations match under your current sync options.", icon: "checkmark.circle")
                    } else if !preview.changes.isEmpty {
                        plannedChanges(preview)
                    }
                    Text("Sizes describe affected file contents, not transfer bytes or space saved. Folder and link sizes are excluded. Unavailable sizes are marked; updates can include metadata only.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if preview.pair.direction == .twoWay {
                    Text("Both directions are compared independently. Each group shows the location that would receive changes. Conflicts use the policy selected in Sync options.")
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
    }

    private func summaryCards(_ preview: SyncPreview) -> some View {
        HStack(spacing: 12) {
            ForEach(PreviewChange.Kind.allCases, id: \.self) { kind in
                let changes = preview.changes.filter { $0.kind == kind }
                let metrics = PreviewMetrics(changes)
                HStack(spacing: 14) {
                    Image(systemName: summarySymbol(kind))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(cardTextColor(kind))
                        .frame(width: 52, height: 52)
                        .background(color(kind).opacity(colorScheme == .dark ? 0.22 : 0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(changes.count.formatted())
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(cardTextColor(kind))
                            .monospacedDigit()
                        Text(summaryTitle(kind))
                            .font(.system(size: 11, weight: .semibold))
                        Text(metrics.countLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(metrics.sizeLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(cardTextColor(kind))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                .cardSurface(radius: 14,
                             fill: color(kind).opacity(colorScheme == .dark ? 0.12 : 0.055),
                             stroke: color(kind).opacity(colorScheme == .dark ? 0.22 : 0.10))
            }
        }
    }

    private func plannedChanges(_ preview: SyncPreview) -> some View {
        let visible = visibleChanges(in: preview)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Planned changes").font(.system(size: 16, weight: .semibold))
                    Text("Here’s what will happen when you sync.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        TextField("Search files and folders…", text: $search)
                            .textFieldStyle(.plain).font(.system(size: 11))
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 250, height: 34)
                    .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.cardStroke) }
                    HStack(spacing: 0) {
                        layoutButton(.list, symbol: "list.bullet")
                        layoutButton(.grid, symbol: "square.grid.2x2")
                    }
                    .padding(2)
                    .background(Palette.cardFill, in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.cardStroke) }
                }
            }

            if visible.isEmpty {
                Text("No planned changes match your search.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 28)
                    .cardSurface(radius: 12)
            } else if changeLayout == .list {
                changeList(visible, allChanges: preview.changes)
            } else {
                changeGrid(visible, allChanges: preview.changes)
            }
        }
    }

    private func layoutButton(_ layout: ChangeLayout, symbol: String) -> some View {
        Button { changeLayout = layout } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(changeLayout == layout ? Palette.accentInk : .secondary)
                .frame(width: 34, height: 30)
                .background(changeLayout == layout ? Palette.accent.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .list ? "List view" : "Grid view")
        .accessibilityAddTraits(changeLayout == layout ? .isSelected : [])
        .help(layout == .list ? "Show as a list" : "Show as a grid")
    }

    private func changeList(_ changes: [PreviewChange], allChanges: [PreviewChange]) -> some View {
        LazyVStack(spacing: 0) {
            HStack(spacing: 12) {
                sortButton("Name", key: .name).frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Change", key: .kind).frame(width: 100, alignment: .leading)
                sortButton("Size", key: .size).frame(width: 105, alignment: .leading)
                sortButton("Type", key: .type).frame(width: 82, alignment: .leading)
                Color.clear.frame(width: 10)
            }
            .padding(.horizontal, 15).frame(height: 36)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(changes) { change in
                HStack(spacing: 12) {
                    HStack(spacing: 11) {
                        Image(systemName: fileSymbol(change))
                            .font(.system(size: 17, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(change.isDirectory ? Palette.accentInk : .secondary)
                            .frame(width: 25)
                        Text(change.relativePath == "." ? URL(fileURLWithPath: change.targetRoot).lastPathComponent : change.relativePath)
                            .font(.system(size: 11, weight: .medium)).lineLimit(1)
                            .truncationMode(.middle).help(change.targetPath)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    changeBadge(change.kind).frame(width: 100, alignment: .leading)
                    Text(displaySize(for: change, allChanges: allChanges))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 105, alignment: .leading)
                    Text(fileType(change))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 82, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .frame(width: 10)
                }
                .padding(.horizontal, 15).frame(minHeight: 43)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .cardSurface(radius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func changeGrid(_ changes: [PreviewChange], allChanges: [PreviewChange]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Image(systemName: fileSymbol(change))
                            .font(.system(size: 24, weight: .medium)).symbolRenderingMode(.hierarchical)
                            .foregroundStyle(change.isDirectory ? Palette.accentInk : .secondary)
                        Spacer()
                        changeBadge(change.kind)
                    }
                    Text(change.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(change.relativePath).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(change.targetPath)
                    HStack {
                        Text(fileType(change))
                        Spacer()
                        Text(displaySize(for: change, allChanges: allChanges))
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(14).frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
                .cardSurface(radius: 12)
            }
        }
    }

    private func sortButton(_ title: String, key: ChangeSort) -> some View {
        Button {
            if changeSort == key { sortAscending.toggle() }
            else { changeSort = key; sortAscending = true }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: changeSort == key ? (sortAscending ? "chevron.up" : "chevron.down") : "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func changeBadge(_ kind: PreviewChange.Kind) -> some View {
        Text(kind.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(cardTextColor(kind))
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(color(kind).opacity(colorScheme == .dark ? 0.20 : 0.11), in: Capsule())
    }

    private func visibleChanges(in preview: SyncPreview) -> [PreviewChange] {
        let matching = preview.changes.filter {
            search.isEmpty || $0.relativePath.localizedCaseInsensitiveContains(search) ||
            $0.targetRoot.localizedCaseInsensitiveContains(search) ||
            $0.kind.rawValue.localizedCaseInsensitiveContains(search) ||
            fileType($0).localizedCaseInsensitiveContains(search)
        }
        return matching.sorted { lhs, rhs in
            let order: ComparisonResult
            switch changeSort {
            case .name: order = lhs.relativePath.localizedStandardCompare(rhs.relativePath)
            case .kind: order = lhs.kind.rawValue.localizedStandardCompare(rhs.kind.rawValue)
            case .size: order = (lhs.size ?? -1) < (rhs.size ?? -1) ? .orderedAscending : (lhs.size == rhs.size ? .orderedSame : .orderedDescending)
            case .type: order = fileType(lhs).localizedStandardCompare(fileType(rhs))
            }
            if order == .orderedSame { return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending }
            return sortAscending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private func displaySize(for change: PreviewChange, allChanges: [PreviewChange]) -> String {
        if change.isLink { return "—" }
        if !change.isDirectory {
            return change.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
        }
        let prefix = change.relativePath == "." ? "" : change.relativePath + "/"
        let descendants = allChanges.filter {
            $0.targetRoot == change.targetRoot && !$0.isDirectory && !$0.isLink &&
            (prefix.isEmpty || $0.relativePath.hasPrefix(prefix))
        }
        guard descendants.contains(where: { $0.size != nil }) else { return "—" }
        let bytes = descendants.compactMap(\.size).reduce(Int64(0), +)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func fileType(_ change: PreviewChange) -> String {
        if change.isDirectory { return "Folder" }
        if change.isLink { return "Link" }
        switch (change.name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "tif", "tiff", "webp", "raw", "dng": return "Image"
        case "mov", "mp4", "m4v", "avi", "mkv": return "Video"
        case "mp3", "m4a", "wav", "aiff", "flac": return "Audio"
        case "zip", "tar", "gz", "7z", "rar": return "Archive"
        case "pdf": return "PDF"
        default: return "File"
        }
    }

    private func fileSymbol(_ change: PreviewChange) -> String {
        switch fileType(change) {
        case "Folder": return "folder.fill"
        case "Link": return "link"
        case "Image": return "photo"
        case "Video": return "film"
        case "Audio": return "waveform"
        case "Archive": return "archivebox.fill"
        case "PDF": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }

    private func summaryTitle(_ kind: PreviewChange.Kind) -> String {
        switch kind {
        case .added: return "Files to be added"
        case .updated: return "Files to be updated"
        case .deleted: return "Files to be deleted"
        }
    }

    private func summarySymbol(_ kind: PreviewChange.Kind) -> String {
        switch kind {
        case .added: return "plus"
        case .updated: return "arrow.triangle.2.circlepath"
        case .deleted: return "minus"
        }
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

}
