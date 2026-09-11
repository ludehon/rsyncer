import SwiftUI
import ServiceManagement

struct AppSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Make yourself at home").font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Toggle("Launch rsyncer at login", isOn: Binding(get: { store.loginEnabled }, set: store.setLoginEnabled)).toggleStyle(.switch)
            if store.loginNeedsApproval {
                Button("Allow rsyncer in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            Text("Closing the window keeps rsyncer in your menu bar, ready for scheduled syncs. Choose Quit rsyncer to stop the app.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            LabeledContent("Sync engine", value: RsyncCommand.executable)
            LabeledContent("Saved history", value: "Latest 250 runs")
            HStack {
                Text("Logs are retained until you remove them.").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Open log folder", action: store.revealLogs)
            }
            Text("For protected folders, macOS may request file access. If a run reports permission errors, review Privacy & Security in System Settings.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(28).frame(width: 510).tint(Palette.green)
            .onAppear { store.refreshLoginStatus() }
    }
}
