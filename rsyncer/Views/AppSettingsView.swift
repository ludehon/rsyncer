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
            VStack(alignment: .leading, spacing: 10) {
                Text("Theme").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, selected: store.theme == theme) {
                            withAnimation(.easeInOut(duration: 0.2)) { store.theme = theme }
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text("Sets the accent color and the sidebar shade across rsyncer.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
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
        }.padding(28).frame(width: 510).tint(Palette.accent)
            .onAppear { store.refreshLoginStatus() }
    }
}

private struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [theme.sidebar, theme.accent, theme.accentBright],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.18)) }
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .opacity(selected ? 1 : 0)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.accent, lineWidth: 2)
                            .padding(-3.5)
                            .opacity(selected ? 1 : 0)
                    }
                Text(theme.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.title)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
