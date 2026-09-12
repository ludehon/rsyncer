import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    var pairID: UUID
    private var records: [RunRecord] { store.history.filter { $0.pairID == pairID } }
    private var isActive: Bool { store.activePairID == pairID }
    private var statusTitle: String {
        if store.cancelling { return "Stopping…" }
        if store.isPaused { return "Paused" }
        if store.fileListStartedAt != nil { return store.isPreview ? "Preparing preview" : "Preparing sync" }
        if store.progress == nil { return store.isPreview ? "Checking for changes" : "Preparing destination" }
        if store.isPreview { return "Comparing files" }
        return store.isTransferring ? "Syncing files" : "Checking files"
    }
    private var isCheckingOnly: Bool { !store.isPreview && store.progress != nil && !store.isTransferring && !store.cancelling && !store.isPaused }
    private var statusDetail: String {
        if store.cancelling { return store.isPreview ? "Waiting for the preview to stop." : "Waiting for the current sync to stop." }
        if store.isPaused { return "Resume when you’re ready to continue." }
        return store.progressDetail
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run history").font(.system(size: 16, weight: .semibold))
                    Text("Every transfer, in one place.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open logs", action: store.revealLogs).font(.system(size: 11))
            }
            if isActive {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(statusTitle).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if let progress = store.progress {
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                        }
                    }
                    if let progress = store.progress {
                        ProgressView(value: progress)
                    } else if store.isPaused || store.cancelling {
                        ProgressView(value: 0)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(statusDetail).font(.system(size: 11)).foregroundStyle(.secondary)
                    if !store.currentItem.isEmpty, !store.cancelling {
                        Text(store.currentItem).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if isCheckingOnly {
                        Text("Files already in sync still have their timestamps refreshed on the destination. This can be slow on encrypted or network volumes.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let started = store.fileListStartedAt, !store.cancelling, !store.isPaused {
                        Text(store.isPreview
                             ? "Waiting for rsync to report progress. It may be reading folders or comparing their contents."
                             : "Waiting for rsync to report progress. It may be reading folders or preparing the destination.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text("Preparation started")
                            Text(started, style: .relative).monospacedDigit()
                            Text("ago")
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 10, fill: Palette.accent.opacity(0.08), stroke: Palette.accent.opacity(0.2))
            }
            if records.isEmpty && !isActive {
                VStack(spacing: 9) {
                    Image(systemName: "text.alignleft").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("A fresh start").font(.system(size: 13, weight: .medium))
                    Text("Run a preview or sync to see its activity here.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            if !records.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        RunHistoryRow(record: record)
                        if record.id != records.last?.id { Divider().padding(.leading, 60) }
                    }
                }
                .cardSurface(radius: 14)
            }
        }
    }
}

private struct RunHistoryRow: View {
    let record: RunRecord
    @State private var expanded = false
    @State private var search = ""

    private var details: [RunChange] {
        guard let items = record.summary?.details else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? items : items.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: record.cancelled ? "stop.circle" : record.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(record.succeeded ? Palette.accentInk : .orange).font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .background((record.succeeded ? Palette.accent : .orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title).font(.system(size: 12, weight: .medium))
                    Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.durationLabel) · exit \(record.exitCode)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if let summary = record.summary, summary.total > 0 {
                        Text(summary.label).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(record.preview ? "Preview" : "Sync")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Palette.insetFill, in: Capsule())
                if record.summary?.details.isEmpty == false {
                    Button { withAnimation { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }.help(expanded ? "Hide changed files" : "Show changed files")
                }
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: record.logPath)) } label: { Image(systemName: "doc.text") }.help("Open run log")
            }
            if expanded {
                TextField("Search changed files", text: $search)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(details.prefix(250)) { item in
                        HStack(spacing: 8) {
                            Text(item.kind.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
                            Text(item.path).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let size = item.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                    }
                    if details.count > 250 {
                        Text("Showing 250 of \(details.count.formatted()) matches").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .padding(10).background(Palette.insetFill, in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
}
