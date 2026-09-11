import Foundation
import Darwin

enum RunEvent: Sendable {
    case output(String)
    case finished(Int32, Bool)
    case failed(String)
}

/// Owns one child process. All output is drained before delivering the final event.
final class RsyncRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var paused = false
    private var suspendedPIDs: [pid_t] = []

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
        // Logs are written before yielding. Slow UI consumers may skip old display
        // batches without losing any on-disk output or the final completion event.
        AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try Data(heading.utf8).write(to: logURL, options: .atomic)
                    let log = try FileHandle(forWritingTo: logURL)
                    defer { try? log.close() }
                    try log.seekToEnd()
                    let child = Process()
                    let pipe = Pipe()
                    child.executableURL = URL(fileURLWithPath: RsyncCommand.executable)
                    child.arguments = arguments
                    var environment = ProcessInfo.processInfo.environment
                    environment["LC_ALL"] = "C"
                    child.environment = environment
                    child.standardOutput = pipe
                    child.standardError = pipe
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
                    pipe.fileHandleForWriting.closeFile()
                    var pending = Data()
                    var logError: Error?
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        do { try log.write(contentsOf: data) } catch {
                            logError = error
                            cancel()
                        }
                        pending.append(data)
                        // Split bytes first so split UTF-8 characters survive pipe boundaries.
                        if let end = pending.lastIndex(where: { $0 == 10 || $0 == 13 }) {
                            let batch = pending.prefix(through: end)
                            continuation.yield(.output(String(decoding: batch, as: UTF8.self)))
                            pending.removeSubrange(...end)
                        }
                        if pending.count > 65_536 {
                            continuation.yield(.output(String(decoding: pending, as: UTF8.self)))
                            pending.removeAll(keepingCapacity: true)
                        }
                    }
                    if !pending.isEmpty { continuation.yield(.output(String(decoding: pending, as: UTF8.self))) }
                    child.waitUntilExit()
                    lock.lock()
                    let wasCancelled = cancelled
                    process = nil
                    _ = resumeLocked()
                    lock.unlock()
                    let footer = "\nFinished: \(Date().formatted()) • Exit code: \(child.terminationStatus)\(wasCancelled ? " • Cancelled" : "")\n"
                    do { try log.write(contentsOf: Data(footer.utf8)) } catch { logError = error }
                    if let logError { continuation.yield(.failed("Could not write the complete log: \(logError.localizedDescription)")) }
                    else { continuation.yield(.finished(child.terminationStatus, wasCancelled)) }
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                }
                continuation.finish()
            }
        }
    }
}
