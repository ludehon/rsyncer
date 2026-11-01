import Foundation

struct SyncConflict: Identifiable, Equatable {
    var id: String { relativePath }
    let relativePath: String
    let sourceDate: Date
    let destinationDate: Date
}

private struct FileFingerprint: Codable, Equatable {
    let size: Int64
    let modified: Date
}

private struct ConflictManifest: Codable {
    var files: [String: FileFingerprint]
}

enum ConflictTracker {
    static func conflicts(for pair: SyncPair, manifestURL: URL) -> [SyncConflict] {
        guard pair.direction == .twoWay, !pair.options.ignoreExisting,
              let data = try? Data(contentsOf: manifestURL),
              let baseline = try? JSONDecoder().decode(ConflictManifest.self, from: data) else { return [] }
        let source = fingerprints(root: RsyncCommand.url(for: pair.source), options: pair.options)
        let destination = fingerprints(root: RsyncCommand.url(for: pair.destination), options: pair.options)
        return baseline.files.compactMap { path, old in
            guard let left = source[path], let right = destination[path],
                  left != old, right != old, left != right else { return nil }
            return SyncConflict(relativePath: path, sourceDate: left.modified, destinationDate: right.modified)
        }.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    static func resolve(_ conflicts: [SyncConflict], for pair: SyncPair) throws {
        guard !conflicts.isEmpty else { return }
        let sourceRoot = RsyncCommand.url(for: pair.source)
        let destinationRoot = RsyncCommand.url(for: pair.destination)
        let manager = FileManager.default
        for conflict in conflicts {
            let source = sourceRoot.appendingPathComponent(conflict.relativePath)
            let destination = destinationRoot.appendingPathComponent(conflict.relativePath)
            switch pair.options.conflictPolicy {
            case .sourceWins:
                try replace(destination, with: source, manager: manager)
            case .destinationWins:
                try replace(source, with: destination, manager: manager)
            case .keepBoth:
                let copy = availableConflictURL(for: destination, manager: manager)
                try manager.copyItem(at: destination, to: copy)
                // Make the source copy canonical for the normal two-pass run. The
                // renamed destination copy then travels back as a separate file.
                try replace(destination, with: source, manager: manager)
            }
        }
    }

    static func saveManifest(for pair: SyncPair, to url: URL) throws {
        let source = fingerprints(root: RsyncCommand.url(for: pair.source), options: pair.options)
        let destination = fingerprints(root: RsyncCommand.url(for: pair.destination), options: pair.options)
        let files = source.filter { destination[$0.key] == $0.value }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ConflictManifest(files: files)).write(to: url, options: .atomic)
    }

    private static func replace(_ target: URL, with winner: URL, manager: FileManager) throws {
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".rsyncer-conflict-\(UUID().uuidString)")
        try manager.copyItem(at: winner, to: temporary)
        _ = try manager.replaceItemAt(target, withItemAt: temporary)
    }

    private static func availableConflictURL(for url: URL, manager: FileManager) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        var number = 1
        while true {
            let suffix = number == 1 ? " (conflict from Destination)" : " (conflict from Destination \(number))"
            let name = stem + suffix + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = folder.appendingPathComponent(name)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private static func fingerprints(root: URL, options: SyncOptions) -> [String: FileFingerprint] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return [:] }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        var result: [String: FileFingerprint] = [:]
        for case let file as URL in enumerator {
            let resolvedFile = file.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedFile.path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(resolvedFile.path.dropFirst(rootPath.count + 1))
            if excluded(relative, options: options) {
                if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { enumerator.skipDescendants() }
                continue
            }
            guard let values = try? resolvedFile.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate else { continue }
            result[relative] = FileFingerprint(size: Int64(size), modified: modified)
        }
        return result
    }

    private static func excluded(_ path: String, options: SyncOptions) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        if options.excludeHidden && components.contains(where: { $0.hasPrefix(".") }) { return true }
        for raw in options.excludePatterns.components(separatedBy: .newlines) {
            let pattern = raw.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { continue }
            if pattern.hasSuffix("/") && components.contains(String(pattern.dropLast())) { return true }
            if !pattern.contains("*") && components.contains(pattern) { return true }
            let expression = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*") + "$"
            if components.contains(where: { $0.range(of: expression, options: .regularExpression) != nil }) { return true }
        }
        return false
    }
}
