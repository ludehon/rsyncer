import Foundation

@main
struct IntegrationTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rsyncer-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source ' $(literal) é")
        let destination = root.appendingPathComponent("destination with spaces")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String, to directory: URL) throws {
            try Data(text.utf8).write(to: directory.appendingPathComponent(name))
        }
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw SyncError.invalid("FAIL: \(message)") }
            print("PASS: \(message)")
        }
        func expectInvalid(_ pair: SyncPair, _ message: String) throws {
            do { try RsyncCommand.validate(pair) } catch { print("PASS: \(message)"); return }
            throw SyncError.invalid("FAIL: \(message)")
        }
        func run(_ pair: SyncPair, preview: Bool = false, worker: RsyncRunner = RsyncRunner()) async throws -> (Int32, Bool, String) {
            let logURL = root.appendingPathComponent("\(UUID()).log")
            var result: (Int32, Bool)?
            var output = ""
            for await event in worker.run(arguments: RsyncCommand.arguments(for: pair, preview: preview), logURL: logURL, heading: "Integration test\n") {
                switch event {
                case .output(let text): output += text
                case .finished(let code, let cancelled): result = (code, cancelled)
                case .failed(let error): throw SyncError.invalid(error)
                }
            }
            guard let result else { throw SyncError.invalid("No completion event") }
            if result.0 != 0 && !result.1 { print("rsync failure: \(output)") }
            let log = try String(contentsOf: logURL, encoding: .utf8)
            try expect(output.isEmpty || log.contains(output), "Full process output reaches log")
            return (result.0, result.1, output)
        }

        try write("hello.txt", "hello world", to: source)
        try write(".DS_Store", "excluded", to: source)
        try write("extra.txt", "keep by default", to: destination)
        try write(".DS_Store", "protected excluded destination file", to: destination)
        try fm.createSymbolicLink(at: source.appendingPathComponent("hello-link"), withDestinationURL: URL(fileURLWithPath: "hello.txt", relativeTo: source))
        var pair = SyncPair(name: "Test", source: source.path, destination: destination.path)
        try RsyncCommand.validate(pair)
        var result = try await run(pair, preview: true)
        try expect(result.0 == 0, "Dry run exits successfully")
        try expect(!fm.fileExists(atPath: destination.appendingPathComponent("hello.txt").path), "Preview does not copy files")
        result = try await run(pair)
        try expect(result.0 == 0, "Default flags work with system rsync")
        let copied = try String(contentsOf: destination.appendingPathComponent("hello.txt"), encoding: .utf8)
        try expect(copied == "hello world", "Contents copied, including quoted / Unicode paths")
        try expect(fm.fileExists(atPath: destination.appendingPathComponent("extra.txt").path), "Extra destination files retained by default")
        let link = try fm.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("hello-link").path)
        try expect(!link.isEmpty, "Symbolic links preserved")
        try expect(!fm.fileExists(atPath: destination.appendingPathComponent(source.lastPathComponent).path), "Folder contents copied without nesting")

        pair.options.deleteExtraneous = true
        result = try await run(pair, preview: true)
        try expect(fm.fileExists(atPath: destination.appendingPathComponent("extra.txt").path), "Preview with deletion still preserves destination files")
        result = try await run(pair)
        try expect(result.0 == 0 && !fm.fileExists(atPath: destination.appendingPathComponent("extra.txt").path), "Opt-in deletion removes extra files")
        let excluded = try String(contentsOf: destination.appendingPathComponent(".DS_Store"), encoding: .utf8)
        try expect(excluded == "protected excluded destination file", "Excluded destination files protected from overwrite and deletion")

        try write("hello.txt", "newer destination", to: destination)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(3600)], ofItemAtPath: destination.appendingPathComponent("hello.txt").path)
        _ = try await run(pair)
        let newer = try String(contentsOf: destination.appendingPathComponent("hello.txt"), encoding: .utf8)
        try expect(newer == "newer destination", "Skip-newer protects destination changes")
        pair.options.skipNewer = false
        pair.options.checksum = true
        pair.options.preservePermissions = true
        pair.options.preserveHardLinks = true
        pair.options.wholeFile = true
        pair.options.compress = true
        result = try await run(pair)
        try expect(result.0 == 0, "Advanced metadata, checksum, hard-link and transfer flags work")
        let restored = try String(contentsOf: destination.appendingPathComponent("hello.txt"), encoding: .utf8)
        try expect(restored == "hello world", "Checksum sync updates differing contents")

        var invalid = pair
        invalid.destination = source.path
        try expectInvalid(invalid, "Identical paths rejected")
        invalid.destination = source.appendingPathComponent("nested").path
        try fm.createDirectory(atPath: invalid.destination, withIntermediateDirectories: true)
        try expectInvalid(invalid, "Nested destination rejected")
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: source)
        invalid.destination = alias.path
        try expectInvalid(invalid, "Symlink aliases cannot bypass overlap checks")
        invalid = pair
        invalid.sourceVolumeID = "wrong-volume"
        try expectInvalid(invalid, "Wrong volume identity rejected")
        invalid = pair
        invalid.destination = root.appendingPathComponent("disconnected").path
        try expectInvalid(invalid, "Missing destination rejected without creating directories")
        invalid = pair
        invalid.source = "relative/path"
        try expectInvalid(invalid, "Relative paths rejected")

        var filePair = pair
        filePair.source = source.appendingPathComponent("hello.txt").path
        filePair.options.deleteExtraneous = false
        result = try await run(filePair)
        try expect(result.0 == 0, "Single-file source supported")
        try expect(TransferProgress.parse(" 1,024  42%  1.2MB/s 0:00:03")?.fraction == 0.42, "Per-file progress parsed")
        try expect(TransferProgress.parse("file.txt") == nil, "Non-progress output ignored")
        try expect(TransferProgress.parse("report 42%.txt") == nil, "Percent signs in filenames are not treated as progress")

        let cancelWorker = RsyncRunner()
        cancelWorker.cancel()
        result = try await run(pair, worker: cancelWorker)
        try expect(result.1, "Cancellation before launch handled")
        try Data(repeating: 65, count: 1024 * 1024).write(to: source.appendingPathComponent("large.bin"))
        pair.options.bandwidthLimit = 32
        pair.options.compress = false
        let activeWorker = RsyncRunner()
        let cancelTask = Task {
            try await Task.sleep(for: .milliseconds(400))
            activeWorker.cancel()
        }
        result = try await run(pair, worker: activeWorker)
        _ = try await cancelTask.value
        try expect(result.1 && result.0 != 0, "Active transfer cancellation terminates the child")
        pair.options.bandwidthLimit = 0

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 10))!
        let daily = SyncSchedule(kind: .daily, hour: 9)
        try expect(daily.nextDate(after: now, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 9)), "Daily schedule advances past today's elapsed time")
        let weekly = SyncSchedule(kind: .weekly, hour: 9, weekday: 2)
        try expect(weekly.nextDate(after: now, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 9)), "Weekly schedule matches chosen weekday")
        try expect(SyncSchedule(kind: .manual).nextDate(after: now) == nil, "Manual schedules never become due")

        let settings = root.appendingPathComponent("settings")
        let store = AppStore(dataDirectory: settings, enableScheduling: false)
        var saved = store.pairs[0]
        saved.name = "Persisted pair"
        saved.source = source.path
        saved.destination = destination.path
        saved.schedule.kind = .hourly
        store.update(saved)
        let reloaded = AppStore(dataDirectory: settings, enableScheduling: false)
        try expect(reloaded.pairs[0].name == "Persisted pair" && reloaded.pairs[0].sourceVolumeID != nil, "Pairs, schedules, and volume identity persist")
        reloaded.pairs[0].nextRun = Date().addingTimeInterval(-60)
        reloaded.tick()
        try expect(reloaded.isRunning, "Overdue scheduled sync starts")
        let deadline = Date().addingTimeInterval(10)
        while reloaded.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try expect(!reloaded.isRunning && reloaded.history.first?.succeeded == true, "Scheduled run completes and records history")
        try expect(reloaded.pairs[0].nextRun! > Date(), "Scheduled run advances next execution time")
        reloaded.pairs[0].destination = root.appendingPathComponent("offline drive").path
        reloaded.pairs[0].nextRun = Date().addingTimeInterval(-60)
        reloaded.tick()
        try expect(!reloaded.isRunning && reloaded.scheduleStatus[reloaded.pairs[0].id] != nil, "Unavailable scheduled location waits without writing")
        let corruptDirectory = root.appendingPathComponent("corrupt")
        try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: corruptDirectory.appendingPathComponent("state.json"))
        let corruptStore = AppStore(dataDirectory: corruptDirectory, enableScheduling: false)
        corruptStore.addPair()
        let preserved = try String(contentsOf: corruptDirectory.appendingPathComponent("state.json"), encoding: .utf8)
        try expect(preserved == "invalid json" && !corruptStore.changesSaved, "Unreadable settings preserved, with unsaved state surfaced")
        print("All integration checks passed.")
    }
}
