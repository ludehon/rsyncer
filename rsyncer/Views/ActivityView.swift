import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedErrorRecord: RunRecord?
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
                Text("Every run, accounted for").font(.system(size: 16, weight: .semibold))
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
                    if !store.runIssues.isEmpty {
                        RunIssueReport(issues: store.runIssues)
                    }
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
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: record.cancelled ? "stop.circle" : record.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(record.succeeded ? Palette.accent : .orange).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title).font(.system(size: 12, weight: .medium))
                            Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.durationLabel) · exit \(record.exitCode)")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            if !record.preview && !record.reportedIssues.isEmpty {
                                Text("\(record.reportedIssues.count) file(s) need attention")
                                    .font(.system(size: 10)).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if record.preview { Text("PREVIEW").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
                        if !record.preview {
                            Button("View errors") { selectedErrorRecord = record }
                                .font(.system(size: 11))
                        }
                        Button { NSWorkspace.shared.open(URL(fileURLWithPath: record.logPath)) } label: { Image(systemName: "doc.text") }.help("Open run log")
                    }
                }.padding(.vertical, 8)
                Divider()
            }
        }
        .sheet(item: $selectedErrorRecord) { record in
            RunErrorSheet(record: record)
        }
    }
}

private struct RunErrorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Files needing attention").font(.title3.weight(.semibold))
                    Text("\(record.pairName) · \(record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !record.reportedIssues.isEmpty {
                    Button("Copy paths") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.reportedIssues.map(\.path).joined(separator: "\n"), forType: .string)
                    }
                }
                Button("Done") { dismiss() }
            }
            Divider()
            if record.reportedIssues.isEmpty {
                Text("No specific uncopied files were identified. This report covers recorded transfer errors and exact excluded paths with missing or shorter destination copies. See the run log for other errors.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open run log") { NSWorkspace.shared.open(URL(fileURLWithPath: record.logPath)) }
                Spacer()
            } else {
                Text("\(record.reportedIssues.count) file(s) need attention. Excluded paths were not transferred in this run.")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(record.reportedIssues) { issue in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(issue.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Text(issue.reasons.map(\.label).sorted().joined(separator: " · "))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 400)
    }
}

private struct RunIssueReport: View {
    let issues: [RunIssue]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.path)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                        Text(issue.reasons.map(\.label).sorted().joined(separator: " · "))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Files needing attention (\(issues.count))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
        }
    }
}
