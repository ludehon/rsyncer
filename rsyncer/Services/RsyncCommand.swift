import Foundation

enum SyncError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

enum RsyncCommand {
    static let executable = "/usr/bin/rsync"

    // Apple's openrsync reports visited entries in to-check; standard rsync
    // reports remaining entries. Probe the executable once, not on every update.
    static let comparisonCountsCompleted: Bool = {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--version"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: output, as: UTF8.self).lowercased().contains("openrsync")
        } catch { return false }
    }()

    static func url(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
    }

    static func volumeID(for path: String) -> String? {
        guard !path.isEmpty else { return nil }
        return try? url(for: path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    static func mountPath(for path: String) -> String? {
        guard !path.isEmpty,
              let values = try? url(for: path).resourceValues(forKeys: [.volumeURLKey]) else { return nil }
        return values.volume?.standardizedFileURL.path
    }

    // Older settings have UUIDs but no saved mount roots. Recover the root for
    // conventional macOS volume paths without trusting the currently mounted disk.
    static func legacyMountPath(for path: String) -> String? {
        let components = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.pathComponents
        guard components.count >= 3, components[1] == "Volumes" else { return nil }
        return "/Volumes/" + components[2]
    }

    static func validate(_ pair: SyncPair) throws {
        let fm = FileManager.default
        for (path, expectedID, savedMountPath, label) in [(pair.source, pair.sourceVolumeID, pair.sourceMountPath, "Source"), (pair.destination, pair.destinationVolumeID, pair.destinationMountPath, "Destination")] {
            guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  path.hasPrefix("/") || path.hasPrefix("~/") else {
                throw SyncError.invalid("\(label) needs an absolute path. Choose a location or enter a path beginning with / or ~/.")
            }
            guard fm.fileExists(atPath: url(for: path).path) else {
                throw SyncError.invalid("\(label) is unavailable. Connect its drive or unlock its vault, then check the path.")
            }
            let expectedMountPath = savedMountPath ?? legacyMountPath(for: path)
            if let expectedMountPath, mountPath(for: path) != expectedMountPath {
                throw SyncError.invalid("\(label)'s volume is not mounted at \(expectedMountPath). Connect its drive or unlock its vault before syncing.")
            }
            // Fall back to UUID for older settings whose mount root is unknown.
            if pair.options.matchVolumesByUUID || expectedMountPath == nil,
               let expectedID, volumeID(for: path) != expectedID {
                throw SyncError.invalid("\(label)'s volume identity has changed. An encrypted vault may receive a new UUID after unlocking. Choose the location again to use this volume.")
            }
        }
        let source = url(for: pair.source)
        let destination = url(for: pair.destination)
        let sourceType = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        guard sourceType.isDirectory == true || sourceType.isRegularFile == true else {
            throw SyncError.invalid("Choose a regular file, folder, or mounted volume as the source.")
        }
        guard source.path != "/", destination.path != "/" else {
            throw SyncError.invalid("Choose a folder within the startup disk, rather than the filesystem root.")
        }
        guard source.path != destination.path,
              !destination.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(destination.path + "/") else {
            throw SyncError.invalid("Source and destination must be separate locations. They cannot contain one another.")
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SyncError.invalid("The destination must be an existing folder or mounted volume.")
        }
        guard fm.isReadableFile(atPath: source.path) else { throw SyncError.invalid("The source is not readable. Check its permissions in Finder.") }
        guard fm.isWritableFile(atPath: destination.path) else { throw SyncError.invalid("The destination is read-only or you do not have permission to write to it.") }
        if pair.direction == .twoWay {
            guard sourceType.isDirectory == true else {
                throw SyncError.invalid("Two-way sync requires two folders or mounted volumes.")
            }
            guard fm.isWritableFile(atPath: source.path), fm.isReadableFile(atPath: destination.path) else {
                throw SyncError.invalid("Two-way sync needs read and write access to both locations.")
            }
        }
        guard pair.options.bandwidthLimit >= 0 else { throw SyncError.invalid("Bandwidth limit cannot be negative.") }
    }

    static func arguments(for pair: SyncPair, preview: Bool) -> [String] {
        var o = pair.options
        if pair.direction == .twoWay {
            o.preserveTimes = true
            o.skipNewer = true
            o.deleteExtraneous = false
        }
        var args = ["--recursive", "--verbose", "--itemize-changes", "--progress", "--stats"]
        // openrsync refreshes every already-synced file's timestamp on the destination
        // before it copies anything, which is slow on FUSE and network volumes and
        // passes in silence at -v. At -vvv its receiver reports each entry as it is
        // examined. Those diagnostics are parsed for progress and kept out of the log.
        // The preview log keeps only genuine changes for its parser.
        if !preview { args += ["--verbose", "--verbose"] }
        let flags: [(Bool, String)] = [
            (o.preserveTimes, "--times"), (o.preservePermissions, "--perms"),
            // Apple's openrsync can fail finalizing AppleDouble files with -E --dry-run.
            // Preview plans file changes; Mac metadata is copied only during the real run.
            (o.preserveLinks, "--links"), (o.extendedAttributes && !preview, "--extended-attributes"),
            (o.checksum, "--checksum"), (o.skipNewer, "--update"),
            (o.ignoreExisting, "--ignore-existing"), (o.deleteExtraneous, "--delete-after"),
            (o.keepPartial, "--partial"), (o.compress, "--compress"),
            (o.wholeFile, "--whole-file"), (o.oneFileSystem, "--one-file-system"),
            (o.preserveHardLinks, "--hard-links"), (preview, "--dry-run")
        ]
        args += flags.filter(\.0).map(\.1)
        // Keep itemized output machine-readable for previews and completed-run summaries.
        args.append("--out-format=RSYNCER2|%i|%l|%n")
        if o.bandwidthLimit > 0 { args.append("--bwlimit=\(o.bandwidthLimit)") }
        if o.excludeHidden { args.append("--exclude=.*") }
        for pattern in o.excludePatterns.components(separatedBy: .newlines) where !pattern.isEmpty {
            args.append("--exclude=\(pattern)")
        }
        var isDirectory: ObjCBool = false
        let source = url(for: pair.source).path
        FileManager.default.fileExists(atPath: source, isDirectory: &isDirectory)
        // Trailing slash copies a directory's contents, avoiding an extra nested folder.
        args += ["--", source + (isDirectory.boolValue ? "/" : ""), url(for: pair.destination).path + "/"]
        return args
    }

    static func passes(for pair: SyncPair, preview: Bool) -> [[String]] {
        var passes = [arguments(for: pair, preview: preview)]
        if pair.direction == .twoWay {
            var reverse = pair
            swap(&reverse.source, &reverse.destination)
            swap(&reverse.sourceVolumeID, &reverse.destinationVolumeID)
            swap(&reverse.sourceMountPath, &reverse.destinationMountPath)
            passes.append(arguments(for: reverse, preview: preview))
        }
        return passes
    }

    static func display(for pair: SyncPair, preview: Bool) -> String {
        passes(for: pair, preview: preview).map { arguments in
            ([executable] + arguments).map {
            "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

struct FileListProgress {
    let count: Int
    let complete: Bool

    static func parse(_ line: String) -> FileListProgress? {
        let text = line.trimmingCharacters(in: .whitespaces)
        // openrsync reports its total after scanning; older rsync can also
        // emit intermediate counts. These totals include directories.
        let patterns = [
            (#"^Transfer starting: ([0-9,]+) files?$"#, true),
            (#"^([0-9,]+) files? to consider$"#, true),
            (#"^(?:building file list \.\.\.\s*)?([0-9,]+) files\.\.\.$"#, false)
        ]
        for (pattern, complete) in patterns {
            guard let match = text.range(of: pattern, options: .regularExpression),
                  let digits = text[match].range(of: #"[0-9][0-9,]*"#, options: .regularExpression),
                  let count = Int(text[digits].replacingOccurrences(of: ",", with: "")) else { continue }
            return FileListProgress(count: count, complete: complete)
        }
        return nil
    }
}

/// Diagnostics openrsync prints at -vv and above, prefixed "rsync(<pid>): : ".
/// Errors and warnings use "rsync(<pid>): error" or "warning" and are never dropped.
enum RsyncOutput {
    static func debugMessage(_ line: String) -> Substring? {
        guard let range = line.range(of: #"^rsync\(\d+\): : "#, options: .regularExpression) else { return nil }
        return line[range.upperBound...]
    }

    static func isDebugLine(_ line: String) -> Bool { debugMessage(line) != nil }

    /// Removes diagnostic lines, keeping every other byte and line ending intact.
    static func strippingDebugLines(_ data: Data) -> Data {
        var kept = Data(capacity: data.count)
        var start = data.startIndex
        while start < data.endIndex {
            var end = start
            while end < data.endIndex, data[end] != 10, data[end] != 13 { end += 1 }
            var next = end
            if next < data.endIndex {
                next += 1
                if data[end] == 13, next < data.endIndex, data[next] == 10 { next += 1 }
            }
            if !hasDebugPrefix(data, from: start, to: end) { kept.append(data[start..<next]) }
            start = next
        }
        return kept
    }

    private static func hasDebugPrefix(_ data: Data, from start: Data.Index, to end: Data.Index) -> Bool {
        var index = start
        for byte in "rsync(".utf8 {
            guard index < end, data[index] == byte else { return false }
            index += 1
        }
        var digits = 0
        while index < end, (48...57).contains(data[index]) { index += 1; digits += 1 }
        guard digits > 0 else { return false }
        for byte in "): : ".utf8 {
            guard index < end, data[index] == byte else { return false }
            index += 1
        }
        return true
    }
}

/// One entry rsync has examined, from whichever line reports it first: the
/// receiver's per-entry diagnostics at -vvv, an openrsync "Skip newer" notice,
/// or an itemized line. Paths are normalized so the same entry compares equal
/// however it was reported.
struct ProcessedItem: Equatable {
    let path: String

    static func parse(_ line: String) -> ProcessedItem? {
        if line.hasPrefix("Skip newer '"), line.hasSuffix("'"), line.count > 13 {
            return ProcessedItem(path: normalize(line.dropFirst(12).dropLast()))
        }
        if let message = RsyncOutput.debugMessage(line) {
            for suffix in [": skipping: up to date", ": updating directory", ": not mapped"] where message.hasSuffix(suffix) {
                let path = message.dropLast(suffix.count)
                return path.isEmpty ? nil : ProcessedItem(path: normalize(path))
            }
            return nil
        }
        // Itemized lines start with the change type and file type followed by
        // attribute flags: ".f        name" from openrsync, ".f...p....." from
        // rsync 3. "*deleting" messages are not entries being checked.
        guard let range = line.range(of: #"^[<>ch.][fdLDS][ .+?a-z]{7,9}\s+(?=\S)"#, options: .regularExpression) else { return nil }
        return ProcessedItem(path: normalize(line[range.upperBound...]))
    }

    private static func normalize(_ path: Substring) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : String(path)
    }
}

struct TransferProgress {
    var fraction: Double
    var detail: String

    static func comparison(_ line: String, countsCompleted: Bool = RsyncCommand.comparisonCountsCompleted) -> TransferProgress? {
        // Dry runs transfer no bytes. Only the completed file-list counter
        // describes comparison progress; ir-chk has a still-growing total.
        guard parse(line) != nil,
              let range = line.range(of: #"\b(?:to-check|to-chk)=([0-9]+)/([0-9]+)"#, options: .regularExpression) else { return nil }
        let counts = line[range].split(separator: "=")[1].split(separator: "/")
        guard counts.count == 2, let count = Int(counts[0]), let total = Int(counts[1]),
              total > 0, count <= total else { return nil }
        let checked = countsCompleted ? count : total - count
        return TransferProgress(fraction: Double(checked) / Double(total),
                                detail: "\(checked.formatted()) of \(total.formatted()) items checked")
    }

    static func parse(_ line: String) -> TransferProgress? {
        guard line.range(of: #"^\s*[\d,]+\s+\d{1,3}%\s"#, options: .regularExpression) != nil,
              let range = line.range(of: #"\b(\d{1,3})%"#, options: .regularExpression),
              let percent = Double(line[range].dropLast()), percent <= 100 else { return nil }
        // rsync 2.6.9 and openrsync expose per-file progress, not total byte progress.
        return TransferProgress(fraction: percent / 100, detail: line.trimmingCharacters(in: .whitespaces))
    }
}
