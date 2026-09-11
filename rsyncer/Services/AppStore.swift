import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    @Published var pairs: [SyncPair] = []
    @Published var history: [RunRecord] = []
    @Published var selectedID: UUID?
    @Published var showingVolumes = false
    @Published var errorMessage: String?
    @Published var activePairID: UUID?
    @Published var activePairName = ""
    @Published var isPreview = false
    @Published var cancelling = false
    @Published var isPaused = false
    @Published var output = ""
    @Published var progress: Double?
    @Published var progressDetail = ""
    @Published var currentLogURL: URL?
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var changesSaved = true
    @Published var scheduleStatus: [UUID: String] = [:]
    let volumes = VolumeMonitor()
    let dataDirectory: URL
    let logsDirectory: URL
    private var runner: RsyncRunner?
    private var timer: Timer?
    private var pendingMounts: Set<UUID> = []
    private var retryAfter: [UUID: Date] = [:]
    private var activity: NSObjectProtocol?
    private var persistenceAvailable = true
    var isRunning: Bool { activePairID != nil }
    var selectedPair: SyncPair? { pairs.first { $0.id == selectedID } }

    init(dataDirectory customDirectory: URL? = nil, enableScheduling: Bool = true) {
        dataDirectory = customDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("rsyncer", isDirectory: true)
        logsDirectory = dataDirectory.appendingPathComponent("Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let stateURL = dataDirectory.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let state = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: stateURL))
                guard state.version == 1 else { throw SyncError.invalid("This settings file was created by a newer version of rsyncer.") }
                pairs = state.pairs
                history = state.history
            }
        } catch {
            persistenceAvailable = false
            changesSaved = false
            errorMessage = "Could not load saved syncs: \(error.localizedDescription) Your existing settings have been left intact."
        }
        if pairs.isEmpty { pairs = [SyncPair(name: "My first sync")] }
        selectedID = pairs.first?.id
        refreshLoginStatus()
        volumes.onMount = { [weak self] url in
            guard let self else { return }
            for pair in self.pairs where pair.schedule.kind == .onMount {
                let root = url.standardizedFileURL.path
                if [pair.source, pair.destination].contains(where: {
                    let path = RsyncCommand.url(for: $0).path
                    return path == root || path.hasPrefix(root + "/")
                }) { self.pendingMounts.insert(pair.id) }
            }
            self.tick()
        }
        if enableScheduling {
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        }
    }

    func save() {
        guard persistenceAvailable else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(PersistedState(pairs: pairs, history: history)).write(to: dataDirectory.appendingPathComponent("state.json"), options: .atomic)
            changesSaved = true
        } catch {
            changesSaved = false
            errorMessage = "Could not save changes: \(error.localizedDescription)"
        }
    }

    func update(_ pair: SyncPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }), activePairID != pair.id else { return }
        var updated = pair
        if pair.source != pairs[index].source { updated.sourceVolumeID = RsyncCommand.volumeID(for: pair.source) }
        if pair.destination != pairs[index].destination { updated.destinationVolumeID = RsyncCommand.volumeID(for: pair.destination) }
        if pair.schedule != pairs[index].schedule {
            updated.nextRun = pair.schedule.nextDate(after: Date())
            pendingMounts.remove(pair.id)
        }
        pairs[index] = updated
        scheduleStatus[pair.id] = nil
        retryAfter[pair.id] = nil
        save()
    }

    func setLocation(_ url: URL, source: Bool, pairID: UUID) {
        guard var pair = pairs.first(where: { $0.id == pairID }) else { return }
        if source { pair.source = url.path; pair.sourceVolumeID = RsyncCommand.volumeID(for: url.path) }
        else { pair.destination = url.path; pair.destinationVolumeID = RsyncCommand.volumeID(for: url.path) }
        if pair.name == "Untitled sync" || pair.name == "My first sync", source { pair.name = url.lastPathComponent }
        update(pair)
    }

    func addPair() {
        let pair = SyncPair()
        pairs.append(pair)
        selectedID = pair.id
        save()
    }

    func removePair(_ id: UUID) {
        guard activePairID != id else { return }
        pairs.removeAll { $0.id == id }
        pendingMounts.remove(id)
        if selectedID == id { selectedID = pairs.first?.id }
        save()
    }

    func renamePair(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var pair = pairs.first(where: { $0.id == id }) else { return }
        pair.name = trimmed
        update(pair)
    }

    func movePair(_ id: UUID, by offset: Int) {
        guard let index = pairs.firstIndex(where: { $0.id == id }), pairs.indices.contains(index + offset) else { return }
        let pair = pairs.remove(at: index)
        pairs.insert(pair, at: index + offset)
        save()
    }

    func chooseLocation(source: Bool, pairID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = source
        panel.allowsMultipleSelection = false
        panel.prompt = source ? "Choose source" : "Choose destination"
        if panel.runModal() == .OK, let url = panel.url { setLocation(url, source: source, pairID: pairID) }
    }

    func start(_ pair: SyncPair, preview: Bool) {
        guard !isRunning else { return }
        do { try RsyncCommand.validate(pair) } catch { errorMessage = error.localizedDescription; return }
        let started = Date()
        let logURL = logsDirectory.appendingPathComponent("\(ISO8601DateFormatter().string(from: started).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString.prefix(8)).log")
        let command = RsyncCommand.display(for: pair, preview: preview)
        let previewNote = preview && pair.options.extendedAttributes ? "\nPreview covers file changes. Extended attributes and resource forks are copied during sync, but are not compared in this preview.\n" : ""
        let heading = "rsyncer • \(pair.name)\n\(preview ? "PREVIEW — no changes will be made" : "SYNC") • \(started.formatted())\n\(command)\n\(previewNote)\n"
        activePairID = pair.id
        activePairName = pair.name
        isPreview = preview
        cancelling = false
        isPaused = false
        progress = nil
        progressDetail = preview ? "Comparing locations…" : "Building file list…"
        output = heading
        currentLogURL = logURL
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Syncing files between volumes")
        let worker = RsyncRunner()
        runner = worker
        Task {
            for await event in worker.run(arguments: RsyncCommand.arguments(for: pair, preview: preview), logURL: logURL, heading: heading) {
                switch event {
                case .output(let chunk):
                    output += chunk.replacingOccurrences(of: "\r", with: "\n")
                    if output.utf8.count > 160_000 { output = String(output.suffix(100_000)) }
                    for line in chunk.components(separatedBy: .newlines) {
                        if let parsed = TransferProgress.parse(line) { progress = parsed.fraction; progressDetail = parsed.detail }
                    }
                case .finished(let code, let cancelled):
                    finish(pair: pair, started: started, preview: preview, code: code, cancelled: cancelled, logURL: logURL)
                case .failed(let message):
                    errorMessage = message
                    finish(pair: pair, started: started, preview: preview, code: -1, cancelled: cancelling, logURL: logURL)
                }
            }
        }
    }

    private func finish(pair: SyncPair, started: Date, preview: Bool, code: Int32, cancelled: Bool, logURL: URL) {
        let record = RunRecord(pairID: pair.id, pairName: pair.name, startedAt: started, finishedAt: Date(), preview: preview, exitCode: code, cancelled: cancelled, logPath: logURL.path)
        history.insert(record, at: 0)
        history = Array(history.prefix(250))
        if let index = pairs.firstIndex(where: { $0.id == pair.id }), !preview {
            pairs[index].lastRun = record.finishedAt
            pairs[index].lastResult = record.title
        }
        output += "\n\(record.title) • Exit code \(code)\n"
        progressDetail = record.title
        progress = record.succeeded ? 1 : nil
        activePairID = nil
        runner = nil
        cancelling = false
        isPaused = false
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if !record.succeeded && !cancelled && errorMessage == nil {
            errorMessage = "rsync exited with code \(code). Some files may not have transferred. Open the run log for details."
        }
        volumes.refresh()
        save()
    }

    func togglePause() {
        guard isRunning, !cancelling, let runner else { return }
        let succeeded = isPaused ? runner.resume() : runner.pause()
        if succeeded { isPaused.toggle() }
        else { errorMessage = "Could not \(isPaused ? "resume" : "pause") the transfer. It may have already finished." }
    }

    func cancel() {
        guard isRunning else { return }
        cancelling = true
        isPaused = false
        progressDetail = "Stopping rsync…"
        runner?.cancel()
    }

    func tick(now: Date = Date()) {
        guard !isRunning else { return }
        for index in pairs.indices {
            let pair = pairs[index]
            guard pair.schedule.kind != .manual else { continue }
            if pair.nextRun == nil, pair.schedule.kind != .onMount {
                pairs[index].nextRun = pair.schedule.nextDate(after: now)
                save()
                continue
            }
            let due = pair.schedule.kind == .onMount ? pendingMounts.contains(pair.id) : (pair.nextRun.map { $0 <= now } ?? false)
            guard due, retryAfter[pair.id].map({ $0 <= now }) ?? true else { continue }
            do { try RsyncCommand.validate(pair) } catch {
                scheduleStatus[pair.id] = error.localizedDescription
                retryAfter[pair.id] = now.addingTimeInterval(60)
                continue
            }
            pendingMounts.remove(pair.id)
            scheduleStatus[pair.id] = nil
            pairs[index].nextRun = pair.schedule.nextDate(after: now)
            save()
            start(pair, preview: false)
            return
        }
    }

    func refreshLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { errorMessage = "Could not update launch at login: \(error.localizedDescription)" }
        refreshLoginStatus()
    }

    func revealLogs() { NSWorkspace.shared.open(logsDirectory) }
}
