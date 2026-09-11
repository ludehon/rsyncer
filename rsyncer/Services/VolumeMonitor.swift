import AppKit
import Combine

struct MountedVolume: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let total: Int64
    let available: Int64
    let isReadOnly: Bool
    let isInternal: Bool
    var usedFraction: Double { total > 0 ? min(1, max(0, Double(total - available) / Double(total))) : 0 }
    var isLow: Bool { total > 0 && Double(available) / Double(total) < 0.1 }
    var status: String { isReadOnly ? "Read-only" : isLow ? "Low space" : "Available" }
    var capacityLabel: String {
        total > 0 ? "\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))" : "Capacity unavailable"
    }
}

@MainActor
final class VolumeMonitor: ObservableObject {
    @Published var volumes: [MountedVolume] = []
    var onMount: ((URL) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                let mounted = notification.name == NSWorkspace.didMountNotification
                Task { @MainActor [weak self] in
                    self?.refresh()
                    if mounted, let url { self?.onMount?(url) }
                }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey, .volumeIsInternalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return MountedVolume(url: url, name: values.volumeName ?? url.lastPathComponent,
                                 total: Int64(values.volumeTotalCapacity ?? 0), available: Int64(values.volumeAvailableCapacity ?? 0),
                                 isReadOnly: values.volumeIsReadOnly ?? true, isInternal: values.volumeIsInternal ?? false)
        }.sorted { ($0.isInternal ? "0" : "1") + $0.name < ($1.isInternal ? "0" : "1") + $1.name }
    }

    func volume(for path: String) -> MountedVolume? {
        guard !path.isEmpty else { return nil }
        let url = RsyncCommand.url(for: path).resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey, .volumeIsInternalKey]),
              let root = values.volume else { return nil }
        return MountedVolume(url: root, name: values.volumeName ?? root.lastPathComponent,
                             total: Int64(values.volumeTotalCapacity ?? 0), available: Int64(values.volumeAvailableCapacity ?? 0),
                             isReadOnly: values.volumeIsReadOnly ?? true, isInternal: values.volumeIsInternal ?? false)
    }
}
