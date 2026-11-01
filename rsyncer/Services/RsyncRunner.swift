import Foundation
import Darwin

enum RunEvent: Sendable {
    case output(String)
    case finished(Int32, Bool)
    case failed(String)
}

enum RunDisplayEvent: Sendable {
    case update(RunDisplayState)
    case finished(Int32, Bool)
    case failed(String)
}

/// Absolute snapshots let the UI skip stale frames without losing item counts.
struct RunDisplayState: Sendable {
    var output: String
    var progress: Double?
    var detail = "Preparing sync…"
    var scanningSince: Date? = Date()
    var itemsTotal = 0
    var itemsChecked = 0
    var currentItem = ""
    var isTransferring = false
    var skippedFiles = 0
    var issues: [RunIssue] = []
}

/// Owned by the background consumer; the UI receives throttled snapshots.
struct RunDisplayAccumulator {
    var state: RunDisplayState
    private var checkedPaths = Set<String>()
    private var lastEmission: TimeInterval = -.infinity
    let preview: Bool

    init(heading: String, preview: Bool) {
        state = RunDisplayState(output: heading, detail: preview ? "Preparing preview…" : "Preparing sync…")
        self.preview = preview
    }

    mutating func consume(_ chunk: String) {
        let clean = RsyncOutput.strippingDebugLines(Data(chunk.utf8))
        state.output += String(decoding: clean, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if state.output.utf8.count > 160_000 { state.output = String(state.output.suffix(100_000)) }
        for line in chunk.components(separatedBy: .newlines) {
            if line == "Pass 1/2: Source → Destination" || line == "Pass 2/2: Destination → Source" {
                state = RunDisplayState(output: state.output, detail: preview ? "Preparing preview…" : "Preparing sync…",
                                        skippedFiles: state.skippedFiles, issues: state.issues)
                checkedPaths.removeAll(keepingCapacity: true)
            }
            if let issue = RunIssue.parse(line) {
                if let index = state.issues.firstIndex(where: { $0.path == issue.path }) {
                    state.issues[index].reasons.formUnion(issue.reasons)
                } else {
                    state.issues.append(issue)
                }
            }
            if line.hasPrefix("Skipped stalled file after ") {
                state.skippedFiles += 1
                state.detail = "Skipped \(state.skippedFiles) stalled file(s); continuing…"
                state.currentItem = ""
                state.isTransferring = false
            }
            if let list = FileListProgress.parse(line) {
                state.progress = nil
                if list.complete {
                    state.scanningSince = nil
                    if !preview { state.itemsTotal = list.count }
                    state.detail = preview
                        ? "Checking \(list.count.formatted()) files and folders for changes…"
                        : "\(list.count.formatted()) items found. Preparing destination and checking changes…"
                } else {
                    state.detail = "Scanning · \(list.count.formatted()) items found"
                }
            }
            if !preview, let item = ProcessedItem.parse(line) {
                let transferringFile = line.hasPrefix(">f") || line.hasPrefix("RSYNCER2|>f")
                if !state.isTransferring || transferringFile { state.currentItem = item.path }
                if checkedPaths.insert(item.path).inserted {
                    state.scanningSince = nil
                    state.itemsChecked = checkedPaths.count
                    if state.itemsTotal > 0 { state.progress = min(0.99, Double(state.itemsChecked) / Double(state.itemsTotal)) }
                    updateItemDetail()
                }
            }
            if let parsed = preview ? TransferProgress.comparison(line) : TransferProgress.parse(line) {
                state.scanningSince = nil
                if !preview { state.isTransferring = true }
                if preview || state.itemsTotal == 0 {
                    state.progress = min(0.99, parsed.fraction)
                    state.detail = parsed.detail
                } else {
                    updateItemDetail()
                }
            }
        }
    }

    mutating func snapshot(at time: TimeInterval, force: Bool = false) -> RunDisplayState? {
        guard force || time - lastEmission >= 0.1 else { return nil }
        lastEmission = time
        return state
    }

    private mutating func updateItemDetail() {
        let count = state.itemsTotal > 0 ? "\(state.itemsChecked.formatted()) of \(state.itemsTotal.formatted()) items" : "\(state.itemsChecked.formatted()) items"
        state.detail = "\(count) checked"
    }
}

/// Watches reported file bytes, not the file-list counter, which can advance
/// while an earlier transfer is blocked in a filesystem read.
final class TransferStallTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?
    private var lastBytes = -1
    private var lastAdvance: TimeInterval = 0
    private var timedOut: String?

    func observe(_ output: String, at time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        for line in output.components(separatedBy: .newlines) {
            if (line.hasPrefix(">f") || line.hasPrefix("RSYNCER2|>f")),
               let item = ProcessedItem.parse(line) {
                path = item.path
                lastBytes = -1
                lastAdvance = time
            } else if path != nil, let progress = TransferProgress.parse(line),
                      let first = line.split(whereSeparator: \.isWhitespace).first,
                      let bytes = Int(first.replacingOccurrences(of: ",", with: "")) {
                if bytes > lastBytes { lastBytes = bytes; lastAdvance = time }
                if progress.fraction == 1 { path = nil }
            }
        }
    }

    func stalledPath(at time: TimeInterval, timeout: TimeInterval, paused: Bool) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if paused { lastAdvance = time; return nil }
        guard timedOut == nil, let path, time - lastAdvance >= timeout else { return nil }
        timedOut = path
        return path
    }

    var skippedPath: String? {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}

/// A terminal makes rsync flush status lines as it does in Terminal, including
/// the file-list heading before a slow destination metadata pass.
private final class RsyncOutputTerminal {
    let reader: FileHandle
    let writer: FileHandle

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        reader = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        writer = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        var attributes = termios()
        guard tcgetattr(slave, &attributes) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        cfmakeraw(&attributes)
        guard tcsetattr(slave, TCSANOW, &attributes) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func read() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(reader.fileDescriptor, &bytes, bytes.count)
            if count >= 0 { return Data(bytes.prefix(count)) }
            if errno == EINTR { continue }
            // A PTY may signal the last slave closing with EIO instead of EOF.
            if errno == EIO { return Data() }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// Owns one child process. All output is drained before delivering the final event.
final class RsyncRunner: @unchecked Sendable {
    private let executableURL: URL
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var paused = false
    private var suspendedPIDs: [pid_t] = []

    init(executableURL: URL = URL(fileURLWithPath: RsyncCommand.executable)) {
        self.executableURL = executableURL
    }

    @discardableResult
    func pause() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        if paused { return true }
        if let process {
            guard process.isRunning, suspendTree(process.processIdentifier) else { return false }
        }
        paused = true
        return true
    }

    @discardableResult
    func resume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumeLocked()
    }

    // Local rsync forks receiver processes. Stop the parent first so it cannot
    // create more children while we walk and suspend the rest of the transfer.
    private func suspendTree(_ pid: pid_t) -> Bool {
        guard kill(pid, SIGSTOP) == 0 else { return false }
        suspendedPIDs.append(pid)
        var children = [pid_t](repeating: 0, count: 32)
        while true {
            let bytes = children.count * MemoryLayout<pid_t>.stride
            let count = proc_listchildpids(pid, &children, Int32(bytes))
            if count < bytes {
                for child in children.prefix(max(0, Int(count)) / MemoryLayout<pid_t>.stride) {
                    _ = suspendTree(child)
                }
                break
            }
            children = [pid_t](repeating: 0, count: children.count * 2)
        }
        return true
    }

    private func resumeLocked() -> Bool {
        suspendedPIDs = suspendedPIDs.reversed().filter { kill($0, SIGCONT) != 0 && errno != ESRCH }
        paused = !suspendedPIDs.isEmpty
        return !paused
    }

    func cancel() {
        lock.lock()
        cancelled = true
        _ = resumeLocked()
        if let process, process.isRunning { process.interrupt() }
        lock.unlock()
        // A stalled filesystem may not respond to SIGINT immediately.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in
            lock.lock()
            if let process, process.isRunning { process.terminate() }
            lock.unlock()
        }
    }

    func run(arguments: [String], logURL: URL, heading: String) -> AsyncStream<RunEvent> {
        run(passes: [arguments], logURL: logURL, heading: heading)
    }

    func runDisplay(passes: [[String]], logURL: URL, heading: String, preview: Bool,
                    plannedDeletions: [PlannedDeletion] = []) -> AsyncStream<RunDisplayEvent> {
        // Only display snapshots may be dropped. The last snapshot and terminal
        // event both fit even when the main thread has stopped consuming frames.
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            Task.detached(priority: .userInitiated) { [self] in
                var display = RunDisplayAccumulator(heading: heading, preview: preview)
                for await event in run(passes: passes, logURL: logURL, heading: heading,
                                       plannedDeletions: plannedDeletions, skipStalledFiles: !preview) {
                    switch event {
                    case .output(let chunk):
                        display.consume(chunk)
                        if let snapshot = display.snapshot(at: ProcessInfo.processInfo.systemUptime) {
                            continuation.yield(.update(snapshot))
                        }
                    case .finished(let code, let cancelled):
                        continuation.yield(.update(display.snapshot(at: ProcessInfo.processInfo.systemUptime, force: true)!))
                        continuation.yield(.finished(code, cancelled))
                    case .failed(let message):
                        continuation.yield(.update(display.snapshot(at: ProcessInfo.processInfo.systemUptime, force: true)!))
                        continuation.yield(.failed(message))
                    }
                }
                continuation.finish()
            }
        }
    }

    func run(passes: [[String]], logURL: URL, heading: String,
             plannedDeletions: [PlannedDeletion] = [], skipStalledFiles: Bool = false,
             stallTimeout: TimeInterval = 30) -> AsyncStream<RunEvent> {
        // Raw events are lossless: the background accumulator must see every item.
        // Only its bounded, cumulative display snapshots can be discarded.
        AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try Data(heading.utf8).write(to: logURL, options: .atomic)
                    let log = try FileHandle(forWritingTo: logURL)
                    defer { try? log.close() }
                    try log.seekToEnd()
                    var finalCode: Int32 = 0
                    var finalCancelled = false
                    var skippedPaths = [String]()
                    for (index, arguments) in passes.enumerated() {
                        var passFailed = false
                        if passes.count > 1 {
                            let label = "\nPass \(index + 1)/\(passes.count): \(index == 0 ? "Source → Destination" : "Destination → Source")\n"
                            try log.write(contentsOf: Data(label.utf8))
                            continuation.yield(.output(label))
                        }
                        var retry = true
                        while retry {
                            retry = false
                            let child = Process()
                            let terminal = try RsyncOutputTerminal()
                            defer {
                                try? terminal.reader.close()
                                try? terminal.writer.close()
                            }
                            child.executableURL = executableURL
                            child.arguments = RsyncCommand.excluding(skippedPaths, from: arguments)
                            var environment = ProcessInfo.processInfo.environment
                            environment["LC_ALL"] = "C"
                            child.environment = environment
                            child.standardOutput = terminal.writer
                            child.standardError = terminal.writer
                            child.standardInput = FileHandle.nullDevice
                            lock.lock()
                            if cancelled {
                                lock.unlock()
                                try log.write(contentsOf: Data("\nCancelled before launch.\n".utf8))
                                continuation.yield(.finished(20, true))
                                continuation.finish()
                                return
                            }
                            process = child
                            do { try child.run() } catch { lock.unlock(); throw error }
                            if paused { _ = suspendTree(child.processIdentifier) }
                            lock.unlock()
                            try terminal.writer.close()
                            let stall = TransferStallTracker()
                            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                            if skipStalledFiles {
                                watchdog.schedule(deadline: .now() + 1, repeating: 1)
                                watchdog.setEventHandler { [self] in
                                    lock.lock()
                                    let stopped = cancelled
                                    let isPaused = paused
                                    lock.unlock()
                                    guard !stopped, child.isRunning,
                                          stall.stalledPath(at: ProcessInfo.processInfo.systemUptime,
                                                            timeout: stallTimeout, paused: isPaused) != nil else { return }
                                    child.interrupt()
                                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                                        if child.isRunning { child.terminate() }
                                    }
                                    DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                                        if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
                                    }
                                }
                            }
                            watchdog.resume()
                            var pending = Data()
                            var logError: Error?
                            while true {
                                let data: Data
                                do { data = try terminal.read() } catch {
                                    logError = error
                                    cancel()
                                    break
                                }
                                if data.isEmpty { break }
                                pending.append(data)
                                // Split bytes first so split UTF-8 characters survive pipe boundaries.
                                // Complete lines are logged without rsync's diagnostics before being yielded.
                                // A trailing CR waits for the LF that may follow so the pair is filtered together.
                                var end = pending.lastIndex(where: { $0 == 10 || $0 == 13 })
                                if let last = end, pending[last] == 13, last == pending.index(before: pending.endIndex) {
                                    end = pending[..<last].lastIndex(where: { $0 == 10 || $0 == 13 })
                                }
                                if let end {
                                    let batch = pending.prefix(through: end)
                                    do { try log.write(contentsOf: RsyncOutput.strippingDebugLines(batch)) } catch {
                                        logError = error
                                        cancel()
                                    }
                                    let chunk = String(decoding: batch, as: UTF8.self)
                                    stall.observe(chunk, at: ProcessInfo.processInfo.systemUptime)
                                    continuation.yield(.output(chunk))
                                    pending.removeSubrange(...end)
                                }
                                if pending.count > 65_536 {
                                    do { try log.write(contentsOf: pending) } catch {
                                        logError = error
                                        cancel()
                                    }
                                    let chunk = String(decoding: pending, as: UTF8.self)
                                    stall.observe(chunk, at: ProcessInfo.processInfo.systemUptime)
                                    continuation.yield(.output(chunk))
                                    pending.removeAll(keepingCapacity: true)
                                }
                            }
                            if !pending.isEmpty {
                                do { try log.write(contentsOf: RsyncOutput.strippingDebugLines(pending)) } catch { logError = error }
                                let chunk = String(decoding: pending, as: UTF8.self)
                                stall.observe(chunk, at: ProcessInfo.processInfo.systemUptime)
                                continuation.yield(.output(chunk))
                            }
                            watchdog.cancel()
                            child.waitUntilExit()
                            lock.lock()
                            let wasCancelled = cancelled
                            process = nil
                            _ = resumeLocked()
                            lock.unlock()
                            let footer = "\nFinished: \(Date().formatted()) • Exit code: \(child.terminationStatus)\(wasCancelled ? " • Cancelled" : "")\n"
                            do { try log.write(contentsOf: Data(footer.utf8)) } catch { logError = error }
                            continuation.yield(.output(footer))
                            if let logError { throw logError }
                            finalCode = child.terminationStatus
                            finalCancelled = wasCancelled
                            if !wasCancelled, let path = stall.skippedPath {
                                finalCode = 23
                                if skippedPaths.contains(path) {
                                    let line = "Stalled file appeared again despite exclusion; stopping: \(path)\n"
                                    try log.write(contentsOf: Data(line.utf8))
                                    continuation.yield(.output(line))
                                    passFailed = true
                                } else {
                                    skippedPaths.append(path)
                                    let line = "Skipped stalled file after \(Int(stallTimeout)) seconds without byte progress: \(path)\n"
                                    try log.write(contentsOf: Data(line.utf8))
                                    continuation.yield(.output(line))
                                    retry = true
                                }
                            } else if finalCode != 0 {
                                passFailed = true
                            }
                        }
                        if passFailed || finalCancelled { break }
                    }
                    if !skippedPaths.isEmpty && !finalCancelled {
                        if finalCode == 0 { finalCode = 23 }
                        let summary = "\nSync incomplete: \(skippedPaths.count) stalled file(s) skipped. See the paths above.\n"
                        try log.write(contentsOf: Data(summary.utf8))
                        continuation.yield(.output(summary))
                    }
                    if skipStalledFiles && !finalCancelled {
                        let logText = try String(contentsOf: logURL, encoding: .utf8)
                        for path in RsyncCommand.shorterSkippedDestinations(in: logText, passes: passes) {
                            let line = "Incomplete newer destination skipped by --update: \(path)\n"
                            try log.write(contentsOf: Data(line.utf8))
                            continuation.yield(.output(line))
                            if finalCode == 0 { finalCode = 23 }
                        }
                        let truncated = Set(logText.components(separatedBy: .newlines).filter {
                            $0.contains(": warning: ") && $0.hasSuffix(": file truncated while reading")
                        })
                        for warning in truncated.sorted() {
                            let line = "Source read warning; transfer may be incomplete: \(warning)\n"
                            try log.write(contentsOf: Data(line.utf8))
                            continuation.yield(.output(line))
                            if finalCode == 0 { finalCode = 23 }
                        }
                    }
                    if finalCode == 0 && !finalCancelled && skippedPaths.isEmpty && !plannedDeletions.isEmpty {
                        for deletion in plannedDeletions { try deletion.validate() }
                        for deletion in plannedDeletions {
                            lock.lock()
                            let stopped = cancelled
                            lock.unlock()
                            if stopped { finalCode = 20; finalCancelled = true; break }
                            try deletion.apply()
                            let line = "Removed previewed item: \(deletion.relativePath)\n"
                            try log.write(contentsOf: Data(line.utf8))
                            continuation.yield(.output(line))
                        }
                    }
                    continuation.yield(.finished(finalCode, finalCancelled))
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
        }
    }
}
