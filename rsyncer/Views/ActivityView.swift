import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    var pairID: UUID
    private var records: [RunRecord] { store.history.filter { $0.pairID == pairID } }
    private var showLiveOutput: Bool { store.activePairID == pairID || (store.activePairID == nil && records.first?.logPath == store.currentLogURL?.path) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Every run, accounted for").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Open logs", action: store.revealLogs).font(.system(size: 11))
            }
            if showLiveOutput && !store.output.isEmpty {
                ScrollView([.vertical, .horizontal]) {
                    Text(store.output).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
                }.frame(height: 190).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                Text("Recent output is shown here. The log file contains the complete run.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if records.isEmpty && !showLiveOutput {
                VStack(spacing: 9) {
                    Image(systemName: "text.alignleft").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("A fresh start").font(.system(size: 13, weight: .medium))
                    Text("Run a preview or sync to see its activity here.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            ForEach(records) { record in
                HStack(spacing: 12) {
                    Image(systemName: record.cancelled ? "stop.circle" : record.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(record.succeeded ? Palette.green : .orange).font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.system(size: 12, weight: .medium))
                        Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(record.finishedAt.timeIntervalSince(record.startedAt)))s · exit \(record.exitCode)")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if record.preview { Text("PREVIEW").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: record.logPath)) } label: { Image(systemName: "doc.text") }.help("Open run log")
                }.padding(.vertical, 8)
                Divider()
            }
        }
    }
}
