import Foundation

enum SyncError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

enum RsyncCommand {
    static let executable = "/usr/bin/rsync"

    static func url(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
    }

    static func volumeID(for path: String) -> String? {
        guard !path.isEmpty else { return nil }
        return try? url(for: path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }

    static func validate(_ pair: SyncPair) throws {
        let fm = FileManager.default
        for (path, expectedID, label) in [(pair.source, pair.sourceVolumeID, "Source"), (pair.destination, pair.destinationVolumeID, "Destination")] {
            guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  path.hasPrefix("/") || path.hasPrefix("~/") else {
                throw SyncError.invalid("\(label) needs an absolute path. Choose a location or enter a path beginning with / or ~/.")
            }
            guard fm.fileExists(atPath: url(for: path).path) else {
                throw SyncError.invalid("\(label) is unavailable. Connect its drive and check the path.")
            }
            if let expectedID, volumeID(for: path) != expectedID {
                throw SyncError.invalid("\(label) is on a different volume than the one you saved. Choose the location again to use this drive.")
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
        guard pair.options.bandwidthLimit >= 0 else { throw SyncError.invalid("Bandwidth limit cannot be negative.") }
    }

    static func arguments(for pair: SyncPair, preview: Bool) -> [String] {
        let o = pair.options
        var args = ["--recursive", "--verbose", "--itemize-changes", "--progress", "--stats"]
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

    static func display(for pair: SyncPair, preview: Bool) -> String {
        ([executable] + arguments(for: pair, preview: preview)).map {
            "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }.joined(separator: " ")
    }
}

struct TransferProgress {
    var fraction: Double
    var detail: String

    static func parse(_ line: String) -> TransferProgress? {
        guard line.range(of: #"^\s*[\d,]+\s+\d{1,3}%\s"#, options: .regularExpression) != nil,
              let range = line.range(of: #"\b(\d{1,3})%"#, options: .regularExpression),
              let percent = Double(line[range].dropLast()), percent <= 100 else { return nil }
        // rsync 2.6.9 and openrsync expose per-file progress, not total byte progress.
        return TransferProgress(fraction: percent / 100, detail: line.trimmingCharacters(in: .whitespaces))
    }
}
