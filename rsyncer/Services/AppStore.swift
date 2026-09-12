import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    private static let hideDockIconWhenClosedKey = "hideDockIconWhenClosed"
    private static let notificationsEnabledKey = "notificationsEnabled"
    private static let notifyOnSuccessKey = "notifyOnSuccess"
    private static let notifyWhenOverdueKey = "notifyWhenOverdue"
    private static let overdueDaysKey = "overdueDays"

    @Published var pairs: [SyncPair] = []
    @Published var history: [RunRecord] = []
    @Published var selectedID: UUID?
    @Published var showingVolumes = false
    @Published var errorMessage: String?
    @Published var activePairID: UUID?
    @Published var activePairName = ""
    @Published var isPreview = false
    @Published var syncPreview: SyncPreview?
    @Published var cancelling = false
    @Published var isPaused = false
    @Published var output = ""
    @Published var progress: Double?
    @Published var progressDetail = ""
    @Published var fileListStartedAt: Date?
    /// Entries rsync has examined so far in the current pass, against the file-list total.
    @Published var itemsChecked = 0
    @Published var itemsTotal = 0
    @Published var currentItem = ""
    @Published var isTransferring = false
    @Published var currentLogURL: URL?
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var changesSaved = true
    @Published var scheduleStatus: [UUID: String] = [:]
    @Published var notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
    @Published var notifyOnSuccess = UserDefaults.standard.bool(forKey: notifyOnSuccessKey)
    @Published var notifyWhenOverdue = UserDefaults.standard.object(forKey: notifyWhenOverdueKey) == nil ? true : UserDefaults.standard.bool(forKey: notifyWhenOverdueKey)
    @Published var overdueDays = max(1, UserDefaults.standard.object(forKey: overdueDaysKey) == nil ? 3 : UserDefaults.standard.integer(forKey: overdueDaysKey))
    @Published var theme = AppTheme.current { didSet { AppTheme.current = theme } }
    @Published var hideDockIconWhenClosed = UserDefaults.standard.object(forKey: hideDockIconWhenClosedKey) == nil
        ? true
        : UserDefaults.standard.bool(forKey: hideDockIconWhenClosedKey) {
        didSet { UserDefaults.standard.set(hideDockIconWhenClosed, forKey: Self.hideDockIconWhenClosedKey) }
    }
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
        updated.direction = pairs[index].direction
        if pair.source != pairs[index].source {
            updated.sourceVolumeID = RsyncCommand.volumeID(for: pair.source)
            updated.sourceMountPath = RsyncCommand.mountPath(for: pair.source)
        }
        if pair.destination != pairs[index].destination {
            updated.destinationVolumeID = RsyncCommand.volumeID(for: pair.destination)
            updated.destinationMountPath = RsyncCommand.mountPath(for: pair.destination)
        }
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
        if source { pair.source = url.path; pair.sourceVolumeID = RsyncCommand.volumeID(for: url.path); pair.sourceMountPath = RsyncCommand.mountPath(for: url.path) }
        else { pair.destination = url.path; pair.destinationVolumeID = RsyncCommand.volumeID(for: url.path); pair.destinationMountPath = RsyncCommand.mountPath(for: url.path) }
        if pair.name == "Untitled sync" || pair.name == "My first sync", source { pair.name = url.lastPathComponent }
        update(pair)
    }

    func addPair(direction: SyncDirection = .oneWay) {
        var pair = SyncPair()
        pair.direction = direction
        pairs.append(pair)
        selectedID = pair.id
        save()
    }

    func duplicatePair(_ id: UUID) {
        guard var copy = pairs.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += " copy"
        copy.lastRun = nil
        copy.lastSuccessfulRun = nil
        copy.lastResult = nil
        copy.nextRun = copy.schedule.nextDate(after: Date())
        pairs.append(copy)
        selectedID = copy.id
        save()
    }

    func exportPair(_ id: UUID) {
        guard let pair = pairs.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(pair.name.isEmpty ? "Sync" : pair.name).rsyncer.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(pair).write(to: url, options: .atomic)
        } catch { errorMessage = "Could not export the saved sync: \(error.localizedDescription)" }
    }

    func importPairs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return }
        do {
            var imported: [SyncPair] = []
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                if let many = try? JSONDecoder().decode([SyncPair].self, from: data) { imported += many }
                else { imported.append(try JSONDecoder().decode(SyncPair.self, from: data)) }
            }
            let now = Date()
            for index in imported.indices {
                imported[index].id = UUID()
                imported[index].lastRun = nil
                imported[index].lastSuccessfulRun = nil
                imported[index].lastResult = nil
                imported[index].nextRun = imported[index].schedule.nextDate(after: now)
            }
            pairs += imported
            selectedID = imported.last?.id ?? selectedID
            save()
        } catch { errorMessage = "Could not import that sync configuration: \(error.localizedDescription)" }
    }

    func removePair(_ id: UUID) {
        guard activePairID != id else { return }
        pairs.removeAll { $0.id == id }
        pendingMounts.remove(id)
        try? FileManager.default.removeItem(at: manifestURL(for: id))
        if selectedID == id { selectedID = pairs.first?.id }
        save()
    }

    func renamePair(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var pair = pairs.first(where: { $0.id == id }) else { return }
        pair.name = trimmed
        update(pair)
    }

    func setConflictPolicy(_ policy: ConflictPolicy, for id: UUID) {
        guard var pair = pairs.first(where: { $0.id == id }) else { return }
        pair.options.conflictPolicy = policy
        update(pair)
        if let preview = syncPreview, preview.pair.id == id,
           let updated = pairs.first(where: { $0.id == id }) {
            syncPreview = SyncPreview(pair: updated, changes: preview.changes, conflicts: preview.conflicts,
                                      complete: preview.complete, succeeded: preview.succeeded)
        }
    }

    func movePair(_ id: UUID, by offset: Int) {
        guard let index = pairs.firstIndex(where: { $0.id == id }), pairs.indices.contains(index + offset) else { return }
        let pair = pairs.remove(at: index)
        pairs.insert(pair, at: index + offset)
        save()
    }

    func chooseLocation(source: Bool, pairID: UUID) {
        let panel = NSOpenPanel()
        let isTwoWay = pairs.first(where: { $0.id == pairID })?.direction == .twoWay
        panel.canChooseDirectories = true
        panel.canChooseFiles = source && !isTwoWay
        panel.allowsMultipleSelection = false
        panel.prompt = isTwoWay ? "Choose Source \(source ? 1 : 2)" : (source ? "Choose source" : "Choose destination")
        if panel.runModal() == .OK, let url = panel.url { setLocation(url, source: source, pairID: pairID) }
    }

    func start(_ pair: SyncPair, preview: Bool) {
        guard !isRunning else { return }
        do { try RsyncCommand.validate(pair) } catch { errorMessage = error.localizedDescription; return }
        let conflicts = ConflictTracker.conflicts(for: pair, manifestURL: manifestURL(for: pair.id))
        if !preview {
            do { try ConflictTracker.resolve(conflicts, for: pair) }
            catch { errorMessage = "Could not preserve the conflicting files: \(error.localizedDescription)"; return }
        }
        let started = Date()
        let logURL = logsDirectory.appendingPathComponent("\(ISO8601DateFormatter().string(from: started).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString.prefix(8)).log")
        let command = RsyncCommand.display(for: pair, preview: preview)
        let previewNote = preview && pair.options.extendedAttributes ? "\nPreview covers file changes. Extended attributes and resource forks are copied during sync, but are not compared in this preview.\n" : ""
        let heading = "rsyncer • \(pair.name)\n\(preview ? "PREVIEW — no changes will be made" : "SYNC") • \(started.formatted())\n\(command)\n\(previewNote)\n"
        activePairID = pair.id
        activePairName = pair.name
        isPreview = preview
        if preview { syncPreview = SyncPreview(pair: pair, conflicts: conflicts) }
        cancelling = false
        isPaused = false
        progress = nil
        fileListStartedAt = started
        progressDetail = preview ? "Preparing preview…" : "Preparing sync…"
        resetItemProgress()
        output = heading
        currentLogURL = logURL
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: preview ? "Previewing file changes" : "Syncing files between volumes")
        let worker = RsyncRunner()
        runner = worker
        Task {
            for await event in worker.runDisplay(passes: RsyncCommand.passes(for: pair, preview: preview), logURL: logURL, heading: heading, preview: preview) {
                switch event {
                case .update(let snapshot):
                    if output != snapshot.output { output = snapshot.output }
                    if progress != snapshot.progress { progress = snapshot.progress }
                    if progressDetail != snapshot.detail { progressDetail = snapshot.detail }
                    if fileListStartedAt != snapshot.scanningSince { fileListStartedAt = snapshot.scanningSince }
                    if itemsTotal != snapshot.itemsTotal { itemsTotal = snapshot.itemsTotal }
                    if itemsChecked != snapshot.itemsChecked { itemsChecked = snapshot.itemsChecked }
                    if currentItem != snapshot.currentItem { currentItem = snapshot.currentItem }
                    if isTransferring != snapshot.isTransferring { isTransferring = snapshot.isTransferring }
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
        var parsedChanges: [PreviewChange] = []
        let previewConflicts = syncPreview?.conflicts ?? []
        if let log = try? String(contentsOf: logURL, encoding: .utf8) {
            parsedChanges = SyncPreview.parse(log, pair: pair)
        }
        if preview {
            if FileManager.default.fileExists(atPath: logURL.path) {
                syncPreview = SyncPreview(pair: pair, changes: parsedChanges, conflicts: previewConflicts,
                                          complete: true, succeeded: code == 0 && !cancelled)
            } else {
                syncPreview = SyncPreview(pair: pair, complete: true)
                errorMessage = "Could not read the completed preview log."
            }
        }
        let summary = makeSummary(parsedChanges)
        let record = RunRecord(pairID: pair.id, pairName: pair.name, startedAt: started, finishedAt: Date(), preview: preview, exitCode: code, cancelled: cancelled, logPath: logURL.path, summary: summary)
        history.insert(record, at: 0)
        history = Array(history.prefix(250))
        if let index = pairs.firstIndex(where: { $0.id == pair.id }), !preview {
            pairs[index].lastRun = record.finishedAt
            pairs[index].lastResult = record.title
            if record.succeeded { pairs[index].lastSuccessfulRun = record.finishedAt }
        }
        if record.succeeded && !preview && pair.direction == .twoWay {
            do { try ConflictTracker.saveManifest(for: pair, to: manifestURL(for: pair.id)) }
            catch { errorMessage = "The sync completed, but its conflict baseline could not be saved: \(error.localizedDescription)" }
        }
        output += "\n\(record.title) • Exit code \(code)\n"
        progressDetail = record.title
        fileListStartedAt = nil
        progress = record.succeeded ? 1 : nil
        currentItem = ""
        isTransferring = false
        activePairID = nil
        runner = nil
        cancelling = false
        isPaused = false
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if !record.succeeded && !cancelled && errorMessage == nil {
            errorMessage = "rsync exited with code \(code). Some files may not have transferred. Open the run log for details."
        }
        if notificationsEnabled && !cancelled {
            if record.succeeded && notifyOnSuccess && !preview {
                AppNotifications.send(title: "Sync complete", body: "\(pair.name): \(summary.label)")
            } else if !record.succeeded {
                AppNotifications.send(title: "Sync needs attention", body: "\(pair.name) finished with exit code \(code).")
            }
        }
        volumes.refresh()
        save()
    }

    private func resetItemProgress() {
        itemsChecked = 0
        itemsTotal = 0
        currentItem = ""
        isTransferring = false
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
        progressDetail = isPreview ? "Stopping preview…" : "Stopping sync…"
        runner?.cancel()
    }

    func tick(now: Date = Date()) {
        checkForOverduePairs(now: now)
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
            if pair.schedule.onlyOnExternalPower && !PowerSource.isUsingExternalPower {
                scheduleStatus[pair.id] = "Waiting for external power."
                retryAfter[pair.id] = now.addingTimeInterval(60)
                continue
            }
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

    func setNotificationsEnabled(_ enabled: Bool) {
        if enabled {
            Task {
                let granted = await AppNotifications.requestAuthorization()
                notificationsEnabled = granted
                UserDefaults.standard.set(granted, forKey: Self.notificationsEnabledKey)
                if !granted { errorMessage = "Notifications are disabled in System Settings." }
            }
        } else {
            notificationsEnabled = false
            UserDefaults.standard.set(false, forKey: Self.notificationsEnabledKey)
        }
    }

    func saveNotificationPreferences() {
        UserDefaults.standard.set(notifyOnSuccess, forKey: Self.notifyOnSuccessKey)
        UserDefaults.standard.set(notifyWhenOverdue, forKey: Self.notifyWhenOverdueKey)
        UserDefaults.standard.set(max(1, overdueDays), forKey: Self.overdueDaysKey)
    }

    private func manifestURL(for id: UUID) -> URL {
        dataDirectory.appendingPathComponent("Manifests", isDirectory: true).appendingPathComponent("\(id.uuidString).json")
    }

    private func makeSummary(_ changes: [PreviewChange]) -> RunSummary {
        var result = RunSummary()
        for change in changes {
            switch change.kind {
            case .added: result.added += 1
            case .updated: result.updated += 1
            case .deleted: result.deleted += 1
            }
            result.bytes += change.size ?? 0
            if result.details.count < 10_000 {
                result.details.append(RunChange(kind: change.kind.rawValue, path: change.relativePath,
                                                targetRoot: change.targetRoot, size: change.size))
            }
        }
        return result
    }

    private func checkForOverduePairs(now: Date) {
        guard notificationsEnabled, notifyWhenOverdue else { return }
        let cutoff = now.addingTimeInterval(-TimeInterval(max(1, overdueDays) * 86_400))
        for pair in pairs where pair.schedule.kind != .manual {
            let reference = pair.lastSuccessfulRun ?? pair.lastRun ?? pair.nextRun
            guard let reference, reference < cutoff else { continue }
            let key = "overdueNotification.\(pair.id.uuidString)"
            if let last = UserDefaults.standard.object(forKey: key) as? Date,
               Calendar.current.isDate(last, inSameDayAs: now) { continue }
            AppNotifications.send(title: "Sync overdue", body: "\(pair.name) has not completed successfully since \(reference.formatted(date: .abbreviated, time: .omitted)).", identifier: key)
            UserDefaults.standard.set(now, forKey: key)
        }
    }
}
