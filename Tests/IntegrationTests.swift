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
        func run(_ pair: SyncPair, preview: Bool = false, worker: RsyncRunner = RsyncRunner(), onOutput: ((String) -> Void)? = nil) async throws -> (Int32, Bool, String) {
            let logURL = root.appendingPathComponent("\(UUID()).log")
            var result: (Int32, Bool)?
            var output = ""
            for await event in worker.run(passes: RsyncCommand.passes(for: pair, preview: preview), logURL: logURL, heading: "Integration test\n") {
                switch event {
                case .output(let text): output += text; onOutput?(text)
                case .finished(let code, let cancelled): result = (code, cancelled)
                case .failed(let error): throw SyncError.invalid(error)
                }
            }
            guard let result else { throw SyncError.invalid("No completion event") }
            if result.0 != 0 && !result.1 { print("rsync failure: \(output)") }
            let log = try Data(contentsOf: logURL)
            // Compare bytes: a trailing CR merges with the footer’s LF into one
            // Swift Character, so String.contains can reject matching output.
            try expect(output.isEmpty || log.range(of: RsyncOutput.strippingDebugLines(Data(output.utf8))) != nil, "Full process output reaches log")
            try expect(log.range(of: Data("): : ".utf8)) == nil, "Run logs omit rsync diagnostics")
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
        let escaped = SyncPreview.parse("RSYNCER|>f+++++++|line\\#012break.txt\n", pair: pair)
        try expect(escaped.first?.relativePath == "line\nbreak.txt", "Visual preview decodes escaped filenames")
        let additions = SyncPreview.parse(result.2, pair: pair)
        try expect(additions.first { $0.name == "hello.txt" }?.size == 11, "Preview captures actual file sizes from rsync")
        let sized = SyncPreview.parse("RSYNCER2|>f+++++++|2048|nested/name|with separator.txt\nRSYNCER2|cd+++++++|4096|nested/\nRSYNCER2|cL+++++++|12|shortcut\nRSYNCER2|>f.s.......|0|empty.txt\n*deleting unknown.txt\n", pair: pair)
        let metrics = PreviewMetrics(sized)
        try expect(sized[0].relativePath == "nested/name|with separator.txt", "Sized preview preserves filename separators")
        try expect(metrics.files == 3 && metrics.folders == 1 && metrics.links == 1, "Summary counts files, folders and links separately")
        try expect(metrics.bytes == 2048 && metrics.unknownSizes == 1, "Summary excludes folder and link sizes and retains unknown sizes")
        try expect(metrics.sizeLabel.hasSuffix("known"), "Partial size totals are identified")
        try expect(PreviewMetrics(Array(sized.suffix(1))).sizeLabel == "Size unavailable", "Missing deletion sizes are not reported as zero")
        try expect(additions.contains { $0.kind == .added && $0.targetPath == destination.appendingPathComponent("hello.txt").path }, "Visual preview maps additions to their exact destination")
        try expect(additions.contains { $0.isLink && $0.name == "hello-link" }, "Visual preview identifies symbolic links")
        let fixture = "RSYNCER|cd+++++++|nested/\nRSYNCER|>f+++++++|nested/name|with spaces.txt\nPass 2/2: Destination → Source\nRSYNCER|>f.s....|ignored short code\nRSYNCER|>f.s.......|changed.txt\n*deleting old.txt\n"
        let planned = SyncPreview.parse(fixture, pair: pair)
        try expect(planned.count == 4 && planned[0].isDirectory, "Visual preview parses folders and rejects malformed item records")
        try expect(planned[1].relativePath == "nested/name|with spaces.txt", "Visual preview preserves spaces and separators in filenames")
        try expect(planned[2].kind == .updated && planned[2].targetRoot == RsyncCommand.url(for: pair.source).path, "Reverse-pass updates target the source")
        try expect(planned[3].kind == .deleted && planned[3].targetRoot == RsyncCommand.url(for: pair.source).path, "Reverse-pass deletions retain their direction")
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
        try expect(SyncPreview.parse(result.2, pair: pair).contains { $0.kind == .deleted && $0.name == "extra.txt" }, "Visual preview identifies actual rsync deletions")
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
        var twoWay = SyncPair(name: "Two-way", source: source.path, destination: destination.path)
        twoWay.direction = .twoWay
        twoWay.options.extendedAttributes = false
        // Safety applies even to inconsistent settings loaded from disk.
        twoWay.options.deleteExtraneous = true
        twoWay.options.skipNewer = false
        twoWay.options.preserveTimes = false
        try RsyncCommand.validate(twoWay)
        try write("left-only.txt", "left", to: source)
        try write("right-only.txt", "right", to: destination)
        try write("hello.txt", "newer right version", to: destination)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(7200)], ofItemAtPath: destination.appendingPathComponent("hello.txt").path)
        result = try await run(twoWay, preview: true)
        try expect(result.0 == 0 && result.2.contains("Pass 2/2"), "Two-way preview checks both directions")
        try expect(!fm.fileExists(atPath: source.appendingPathComponent("right-only.txt").path) && !fm.fileExists(atPath: destination.appendingPathComponent("left-only.txt").path), "Two-way preview writes to neither side")
        result = try await run(twoWay)
        let merged = try String(contentsOf: source.appendingPathComponent("hello.txt"), encoding: .utf8)
        try expect(result.0 == 0 && merged == "newer right version", "Two-way sync brings back newer destination content")
        try expect(fm.fileExists(atPath: source.appendingPathComponent("right-only.txt").path) && fm.fileExists(atPath: destination.appendingPathComponent("left-only.txt").path), "Two-way sync merges files unique to either side without deleting them")
        let cancelledTwoWay = RsyncRunner()
        cancelledTwoWay.cancel()
        result = try await run(twoWay, worker: cancelledTwoWay)
        try expect(result.1 && !result.2.contains("Pass 2/2"), "Cancelled two-way run does not start the reverse pass")
        var invalidTwoWay = twoWay
        invalidTwoWay.source = filePair.source
        try expectInvalid(invalidTwoWay, "Two-way sync rejects single-file sources")
        let encodedTwoWay = try JSONEncoder().encode(twoWay)
        let decodedTwoWay = try JSONDecoder().decode(SyncPair.self, from: encodedTwoWay)
        try expect(decodedTwoWay.direction == .twoWay, "Two-way selection survives persistence")
        var legacyJSON = try JSONSerialization.jsonObject(with: encodedTwoWay) as! [String: Any]
        legacyJSON.removeValue(forKey: "savedDirection")
        let legacy = try JSONDecoder().decode(SyncPair.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        try expect(legacy.direction == .oneWay, "Existing saved syncs default to one-way")

        try expect(TransferProgress.parse(" 1,024  42%  1.2MB/s 0:00:03")?.fraction == 0.42, "Per-file progress parsed")
        let comparison = TransferProgress.comparison("0  0%  00:00:00 (xfer#6480, to-check=16579/18319)", countsCompleted: true)
        try expect(comparison != nil && abs(comparison!.fraction - 16579.0 / 18319.0) < 0.000001, "Dry-run progress uses checked items despite zero transferred bytes")
        try expect(TransferProgress.comparison("0 0% 00:00:00 (xfer#3, to-chk=0/100)", countsCompleted: false)?.fraction == 1, "Completed comparison reaches 100 percent")
        let ascending = [2, 3, 4, 5, 6, 7, 8].compactMap {
            TransferProgress.comparison("0 0% 00:00:00 (xfer#1, to-check=\($0)/9)", countsCompleted: true)?.fraction
        }
        try expect(ascending.count == 7 && zip(ascending, ascending.dropFirst()).allSatisfy { $0 < $1 }, "Captured openrsync counters advance the preview bar forward")
        try expect(TransferProgress.comparison("0 0% 00:00:00 (to-check=100/100)", countsCompleted: true)?.fraction == 1, "Openrsync completed count reaches 100 percent")
        let descending = [8, 7, 6, 5, 4, 3, 2].compactMap {
            TransferProgress.comparison("0 0% 00:00:00 (xfer#1, to-check=\($0)/9)", countsCompleted: false)?.fraction
        }
        try expect(zip(descending, descending.dropFirst()).allSatisfy { $0 < $1 }, "Standard rsync remaining counters also advance forward")
        try expect(TransferProgress.comparison("0 0% 00:00:00 (to-check=0/0)") == nil, "Empty comparison avoids division by zero")
        try expect(TransferProgress.comparison("0 0% 00:00:00 (to-check=101/100)") == nil, "Invalid comparison counts ignored")
        try expect(TransferProgress.comparison("0 0% 00:00:00 (ir-chk=10/100)") == nil, "Growing file lists do not report a fixed percentage")
        try expect(TransferProgress.comparison("0 0% 00:00:00") == nil, "Dry-run byte percentage without counts is ignored")
        try expect(TransferProgress.comparison("RSYNCER2|>f+++++++|0|to-check=0/100") == nil, "Filenames cannot spoof comparison progress")
        try expect(TransferProgress.parse("file.txt") == nil, "Non-progress output ignored")
        let fileList = FileListProgress.parse("Transfer starting: 18,319 files")
        try expect(fileList?.count == 18319 && fileList?.complete == true, "Openrsync file-list total includes files and folders")
        try expect(FileListProgress.parse("  1200 files...")?.complete == false, "Intermediate scan counts stay indeterminate")
        try expect(FileListProgress.parse("building file list ... 100 files...")?.count == 100, "Initial legacy scan count parsed")
        try expect(FileListProgress.parse("1 file to consider")?.complete == true, "Legacy scan completion parsed")
        try expect(FileListProgress.parse("RSYNCER2|>f+++++++|0|Transfer starting: 100 files") == nil, "Itemized filenames cannot spoof scan counts")
        try expect(FileListProgress.parse("Transfer starting: -1 files") == nil, "Invalid scan counts ignored")
        try expect(TransferProgress.parse("report 42%.txt") == nil, "Percent signs in filenames are not treated as progress")
        try expect(ProcessedItem.parse(".f        jpg_ams/DSC00596.jpg") == ProcessedItem(path: "jpg_ams/DSC00596.jpg"), "Openrsync up-to-date entries count as checked items")
        try expect(ProcessedItem.parse("rsync(4242): : sub/same.txt: skipping: up to date") == ProcessedItem(path: "sub/same.txt"), "Receiver diagnostics report each unchanged file as it is examined")
        try expect(ProcessedItem.parse("rsync(4242): : newfile.txt: not mapped") == ProcessedItem(path: "newfile.txt"), "Receiver diagnostics report files that will be copied")
        try expect(ProcessedItem.parse("rsync(4242): : BIRDS/RAW: updating directory") == ProcessedItem.parse(".d..t.... BIRDS/RAW/"), "Directories compare equal whether reported by the receiver or itemized")
        try expect(ProcessedItem.parse("rsync(4242): : .: updating directory") == ProcessedItem.parse(".d        ./"), "The destination root compares equal in both reports")
        try expect(ProcessedItem.parse(">f..t.... newer.txt")?.path == "newer.txt", "Transferred files are recognised")
        try expect(ProcessedItem.parse(".f...p..... a  b.txt")?.path == "a  b.txt", "Standard rsync itemized entries keep their full path")
        try expect(ProcessedItem.parse("Skip newer 'to sort/DSC01475.tif'")?.path == "to sort/DSC01475.tif", "Files skipped for being newer count as checked items")
        try expect(ProcessedItem.parse("rsync(4242): : src/big.bin: read block prologue: 0 blocks") == nil && ProcessedItem.parse("rsync(4242): : downloader: phase complete") == nil, "Other diagnostics are not items")
        try expect(ProcessedItem.parse("*deleting old.txt") == nil, "Deletions are not counted as checked items")
        try expect(ProcessedItem.parse("RSYNCER2|>f+++++++|0|x") == nil && ProcessedItem.parse("Transfer starting: 10 files") == nil, "Preview and scan lines are not items")
        try expect(ProcessedItem.parse("     1,024  42%  1.2MB/s 0:00:03") == nil && ProcessedItem.parse("sent 9865 bytes  received 1394 bytes") == nil, "Progress and summary lines are not items")
        try expect(ProcessedItem.parse(".f        ") == nil && ProcessedItem.parse("Skip newer ''") == nil && ProcessedItem.parse("rsync(1): : : skipping: up to date") == nil, "Entries without a path are ignored")
        try expect(RsyncOutput.isDebugLine("rsync(4242): : a: skipping: up to date") && !RsyncOutput.isDebugLine("rsync(4242): error: boom") && !RsyncOutput.isDebugLine("rsync(4242): warning: hmm"), "Only diagnostics are treated as debug output")
        let noisy = Data("Transfer starting: 3 files\r\nrsync(1): : a: skipping: up to date\r\n>f+++++++ b\nrsync(1): error: boom\nrsync(1): : tail".utf8)
        try expect(String(decoding: RsyncOutput.strippingDebugLines(noisy), as: UTF8.self) == "Transfer starting: 3 files\r\n>f+++++++ b\nrsync(1): error: boom\n", "Run logs drop diagnostics but keep output, errors, and line endings")
        try expect(RsyncOutput.strippingDebugLines(Data("plain\n".utf8).dropFirst(0)).count == 6, "Stripping keeps ordinary output unchanged")
        try expect(RsyncCommand.arguments(for: pair, preview: false).filter { $0 == "--verbose" }.count == 3, "Sync asks the receiver to report each entry so checking progress is visible")
        try expect(RsyncCommand.arguments(for: pair, preview: true).filter { $0 == "--verbose" }.count == 1, "Preview keeps the quieter log its parser expects")

        let cancelWorker = RsyncRunner()
        cancelWorker.cancel()
        result = try await run(pair, worker: cancelWorker)
        try expect(result.1, "Cancellation before launch handled")
        try Data(repeating: 65, count: 4 * 1024 * 1024).write(to: source.appendingPathComponent("large.bin"))
        pair.options.bandwidthLimit = 512
        pair.options.compress = false
        let activeWorker = RsyncRunner()
        var sawLiveFileList = false
        var sawLivePercentage = false
        var sawProcessedItem = false
        let cancelTask = Task {
            defer { activeWorker.cancel() }
            try await Task.sleep(for: .milliseconds(400))
            try expect(activeWorker.pause(), "Active transfer can be paused")
            func destinationBytes() -> Int {
                let files = (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
            }
            try await Task.sleep(for: .milliseconds(300))
            let pausedBytes = destinationBytes()
            try await Task.sleep(for: .milliseconds(1200))
            try expect(destinationBytes() == pausedBytes, "Paused transfer stops destination writes")
            try expect(activeWorker.resume(), "Paused transfer can resume")
            try await Task.sleep(for: .seconds(2))
            try expect(destinationBytes() > pausedBytes, "Resumed transfer continues writing")
            try expect(sawLiveFileList && sawLivePercentage, "File-list total and percentage arrive while the transfer is still running")
            try expect(sawProcessedItem, "Checked entries are itemized while the transfer is still running")
            try expect(activeWorker.pause(), "Resumed transfer can pause again before cancellation")
        }
        result = try await run(pair, worker: activeWorker) { chunk in
            for line in chunk.components(separatedBy: .newlines) {
                if FileListProgress.parse(line)?.complete == true { sawLiveFileList = true }
                if TransferProgress.parse(line) != nil { sawLivePercentage = true }
                if ProcessedItem.parse(line) != nil { sawProcessedItem = true }
            }
        }
        _ = try await cancelTask.value
        try expect(result.1 && result.0 != 0, "Cancelling a paused transfer terminates the child")
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
        store.start(pair, preview: true)
        try expect(store.syncPreview?.complete == false, "Visual preview begins in the comparing state")
        while store.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        try expect(store.syncPreview?.complete == true && store.syncPreview?.succeeded == true, "Visual preview loads the completed log into the store")
        var saved = store.pairs[0]
        saved.name = "Persisted pair"
        saved.source = source.path
        saved.destination = destination.path
        saved.schedule.kind = .hourly
        store.update(saved)
        let reloaded = AppStore(dataDirectory: settings, enableScheduling: false)
        try expect(reloaded.pairs[0].name == "Persisted pair" && reloaded.pairs[0].sourceVolumeID != nil, "Pairs, schedules, and volume identity persist")
        let slots: [CGFloat] = [29, 93, 157, 221]
        try expect(SyncReorder.destination(for: 105, slotCenters: slots) == 1, "Dragging down crosses into the next row before release")
        try expect(SyncReorder.destination(for: 80, slotCenters: slots) == 1, "Dragging up crosses into the previous row before release")
        try expect(SyncReorder.destination(for: -50, slotCenters: slots) == 0, "Dragging above the list clamps to the first slot")
        try expect(SyncReorder.destination(for: 400, slotCenters: slots) == 3, "Dragging below the list clamps to the last slot")
        try expect(SyncReorder.destination(for: 0, slotCenters: []) == nil, "Empty lists have no reorder target")
        store.addPair(direction: .twoWay)
        var attemptedDirectionChange = store.selectedPair!
        attemptedDirectionChange.direction = .oneWay
        store.update(attemptedDirectionChange)
        try expect(store.selectedPair?.direction == .twoWay, "Direction chosen at creation cannot be changed by editing a sync")
        let addedID = store.selectedID!
        store.renamePair(addedID, to: "  Second sync  ")
        store.movePair(addedID, by: -1)
        let reordered = AppStore(dataDirectory: settings, enableScheduling: false)
        try expect(reordered.pairs.first?.direction == .twoWay, "Direction chosen in the add menu survives reload")
        try expect(reordered.pairs.first?.id == addedID && reordered.pairs.first?.name == "Second sync", "Renaming and reordering survive reload")
        store.movePair(addedID, by: -1)
        try expect(store.pairs.first?.id == addedID && store.selectedID == addedID, "Moving past the top preserves order and selection")
        store.movePair(addedID, by: 1)
        try expect(store.pairs.last?.id == addedID, "Saved sync can move down")
        try expect(store.volumes.volume(for: source.appendingPathComponent("hello.txt").path)?.total ?? 0 > 0, "File source resolves to volume capacity")
        try expect(store.volumes.volume(for: alias.path)?.url == store.volumes.volume(for: source.path)?.url, "Symlink source resolves to the target volume")
        try expect(store.volumes.volume(for: root.appendingPathComponent("missing").path) == nil, "Unavailable location does not report another volume's capacity")
        reloaded.pairs[0].nextRun = Date().addingTimeInterval(-60)
        reloaded.tick()
        try expect(reloaded.isRunning, "Overdue scheduled sync starts")
        reloaded.togglePause()
        try expect(reloaded.isPaused && reloaded.isRunning, "Pausing preserves the active sync")
        reloaded.togglePause()
        try expect(!reloaded.isPaused && reloaded.isRunning, "Resuming preserves the active sync")
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
