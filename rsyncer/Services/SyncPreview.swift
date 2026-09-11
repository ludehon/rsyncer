import Foundation

struct PreviewChange: Identifiable {
    enum Kind: String, CaseIterable { case added = "Added", updated = "Updated", deleted = "Deleted" }
    let id: Int
    let kind: Kind
    let relativePath: String
    let targetRoot: String
    let isDirectory: Bool
    let isLink: Bool
    var size: Int64? = nil
    var targetPath: String { targetRoot + (relativePath == "." ? "" : "/" + relativePath) }
    var folder: String { (targetPath as NSString).deletingLastPathComponent }
    var name: String { (targetPath as NSString).lastPathComponent }
}

struct SyncPreview {
    let pair: SyncPair
    var changes: [PreviewChange] = []
    var complete = false
    var succeeded = false

    // Read the complete on-disk output, not the bounded live-output buffer.
    private static func decodeFilename(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var decoded: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if index + 4 < bytes.count, bytes[index] == 92, bytes[index + 1] == 35,
               bytes[(index + 2)...(index + 4)].allSatisfy({ (48...55).contains($0) }),
               let byte = UInt8(String(decoding: bytes[(index + 2)...(index + 4)], as: UTF8.self), radix: 8) {
                decoded.append(byte)
                index += 5
            } else {
                decoded.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: decoded, as: UTF8.self)
    }

    static func parse(_ log: String, pair: SyncPair) -> [PreviewChange] {
        var target = RsyncCommand.url(for: pair.destination).path
        var changes: [PreviewChange] = []
        for line in log.components(separatedBy: .newlines) {
            if line == "Pass 2/2: Destination → Source" {
                target = RsyncCommand.url(for: pair.source).path
                continue
            }
            var path: String
            var size: Int64?
            let kind: PreviewChange.Kind
            var directory = false
            var link = false
            if line.hasPrefix("*deleting ") {
                path = String(line.dropFirst(10))
                kind = .deleted
                directory = path.hasSuffix("/")
            } else if line.hasPrefix("RSYNCER|") || line.hasPrefix("RSYNCER2|") {
                let hasSize = line.hasPrefix("RSYNCER2|")
                let fields = line.split(separator: "|", maxSplits: hasSize ? 3 : 2, omittingEmptySubsequences: false)
                guard fields.count == (hasSize ? 4 : 3) else { continue }
                let code = String(fields[1])
                path = String(fields[hasSize ? 3 : 2])
                if hasSize, let bytes = Int64(fields[2]), bytes >= 0 { size = bytes }
                if code.hasPrefix("*deleting") {
                    kind = .deleted
                    directory = path.hasSuffix("/")
                } else {
                    guard code.count >= 9, let type = code.dropFirst().first,
                          "fdLDS".contains(type) else { continue }
                    directory = type == "d"
                    link = type == "L"
                    kind = code.contains("+") ? .added : .updated
                }
            } else { continue }
            path = decodeFilename(path)
            while path.hasPrefix("./") { path = String(path.dropFirst(2)) }
            if path.hasSuffix("/") { path.removeLast() }
            if path.isEmpty { path = "." }
            changes.append(PreviewChange(id: changes.count, kind: kind, relativePath: path,
                                         targetRoot: target, isDirectory: directory, isLink: link, size: size))
        }
        return changes
    }
}

/// Logical sizes of affected files, excluding folder metadata and link targets.
struct PreviewMetrics {
    var files = 0
    var folders = 0
    var links = 0
    var bytes: Int64 = 0
    var unknownSizes = 0

    init(_ changes: [PreviewChange]) {
        for change in changes {
            if change.isDirectory { folders += 1 }
            else if change.isLink { links += 1 }
            else {
                files += 1
                if let size = change.size { bytes += size }
                else { unknownSizes += 1 }
            }
        }
    }

    var sizeLabel: String {
        if files > 0 && unknownSizes == files { return "Size unavailable" }
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return unknownSizes > 0 ? "\(formatted) known" : formatted
    }

    var countLabel: String {
        "\(files.formatted()) \(files == 1 ? "file" : "files") · \(folders.formatted()) \(folders == 1 ? "folder" : "folders")" + (links > 0 ? " · \(links.formatted()) \(links == 1 ? "link" : "links")" : "")
    }
}
