import SwiftUI

struct VolumesView: View {
    @ObservedObject var monitor: VolumeMonitor
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A home for your files.").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Connected volumes, with a little breathing room.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh volumes")
                }
                ForEach(monitor.volumes) { volume in
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(spacing: 15) {
                            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill").font(.system(size: 32)).foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(volume.name).font(.system(size: 16, weight: .semibold))
                                Text(volume.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label(volume.status, systemImage: volume.isReadOnly ? "lock.fill" : volume.isLow ? "exclamationmark.circle.fill" : "circle.fill")
                                .font(.system(size: 10)).foregroundStyle(volume.isReadOnly || volume.isLow ? .orange : Palette.accent)
                            Button { NSWorkspace.shared.open(volume.url) } label: { Image(systemName: "arrow.up.right.square") }.help("Open volume in Finder")
                        }
                        ProgressView(value: volume.usedFraction).tint(volume.isLow ? .orange : Palette.accent)
                        Text(volume.capacityLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(22).cardSurface()
                }
                Label("Status reflects free space and write access. Hardware health / SMART is not assessed. Use Disk Utility for disk diagnostics.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(32)
        }
    }
}
