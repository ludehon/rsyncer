import SwiftUI

enum Palette {
    static let green = Color(red: 0.19, green: 0.43, blue: 0.34)
    static let sidebar = Color(red: 0.09, green: 0.15, blue: 0.14)
    static let canvas = Color(nsColor: .windowBackgroundColor)
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false
    private var showVolumes: Bool { store.showingVolumes }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 238)
            Group {
                if showVolumes {
                    VolumesView(monitor: store.volumes)
                } else if let pair = store.selectedPair {
                    PairDetailView(pairID: pair.id).id(pair.id)
                } else {
                    ContentUnavailableView {
                        Label("Make room for a little order", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Save a pair of locations to start your first sync.")
                    } actions: {
                        Button("Create a sync", action: store.addPair).buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
        }
        .frame(minWidth: 980, minHeight: 720)
        .tint(Palette.green)
        .sheet(isPresented: $showSettings) { AppSettingsView().environmentObject(store) }
        .alert("rsyncer needs your attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color(red: 0.65, green: 0.85, blue: 0.62))
                Text("rsyncer").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 8)
            Text("A place for everything.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 24).padding(.bottom, 38)
            HStack {
                Text("SAVED SYNCS").font(.system(size: 10, weight: .semibold)).tracking(1.6)
                Spacer()
                Button { store.addPair(); store.showingVolumes = false } label: { Image(systemName: "plus").font(.system(size: 13)) }
                    .buttonStyle(.plain).help("New sync pair")
            }.foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 24).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.pairs) { pair in
                        Button { store.selectedID = pair.id; store.showingVolumes = false } label: {
                            HStack(spacing: 12) {
                                Image(systemName: store.activePairID == pair.id ? "arrow.triangle.2.circlepath" : "folder")
                                    .font(.system(size: 17))
                                    .foregroundStyle(store.selectedID == pair.id && !showVolumes ? Color(red: 0.69, green: 0.87, blue: 0.68) : .white.opacity(0.5))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(pair.name.isEmpty ? "Untitled sync" : pair.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(store.activePairID == pair.id ? "In progress" : pair.schedule.kind == .manual ? "On your terms" : pair.schedule.kind.title)
                                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                                }
                                Spacer(minLength: 0)
                                if pair.schedule.kind != .manual { Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(store.selectedID == pair.id && !showVolumes ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 20)
            SidebarVolumes(monitor: store.volumes) { store.showingVolumes = true }
            Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 24).padding(.vertical, 20)
            Button { showSettings = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Settings").font(.system(size: 12))
                    Spacer()
                    Text("1.0").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                }.foregroundStyle(.white.opacity(0.65))
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 24)
        }
        .foregroundStyle(.white)
        .background(Palette.sidebar)
    }
}

struct SidebarVolumes: View {
    @ObservedObject var monitor: VolumeMonitor
    var action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CONNECTED DRIVES").font(.system(size: 10, weight: .semibold)).tracking(1.3)
                Spacer()
                Text("\(monitor.volumes.count)").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.white.opacity(0.45))
            ForEach(monitor.volumes.prefix(4)) { volume in
                Button(action: action) {
                    HStack(spacing: 10) {
                        Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive").font(.system(size: 17))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(volume.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            Text(volume.status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                        Circle().fill(volume.isLow || volume.isReadOnly ? .orange : Color(red: 0.62, green: 0.81, blue: 0.55)).frame(width: 5, height: 5)
                    }.foregroundStyle(.white.opacity(0.75))
                }.buttonStyle(.plain)
            }
            Button("View all drives", action: action).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
        }.padding(.horizontal, 24)
    }
}
