import Foundation
import Darwin

struct SyncOptions: Codable, Equatable {
    // Optional storage keeps settings from older releases decodable.
    var savedMatchVolumesByUUID: Bool?
    var matchVolumesByUUID: Bool {
        get { savedMatchVolumesByUUID ?? false }
        set { savedMatchVolumesByUUID = newValue }
    }
    var preserveTimes = true
    var preservePermissions = false
    var preserveLinks = true
    var extendedAttributes = false
    var checksum = false
    var skipNewer = true
    var ignoreExisting = false
    var deleteExtraneous = false
    var keepPartial = true
    var compress = false
    var wholeFile = false
    var oneFileSystem = true
    var preserveHardLinks = false
    var excludeHidden = false
    var excludePatterns = ".DS_Store\n.Trashes\n.Spotlight-V100\n.fseventsd"
    var bandwidthLimit = 0
}

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case manual, hourly, daily, weekly, onMount
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: "Manual only"
        case .hourly: "Every hour"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .onMount: "When a drive connects"
        }
    }
}

struct SyncSchedule: Codable, Equatable {
    var kind: ScheduleKind = .manual
    var hour = 9
    var minute = 0
    var weekday = 2

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch kind {
        case .manual, .onMount: return nil
        case .hourly: return date.addingTimeInterval(3600)
        case .daily: return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
        case .weekly: return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, weekday: weekday), matchingPolicy: .nextTime)
        }
    }
}

enum SyncDirection: String, Codable, CaseIterable, Identifiable {
    case oneWay, twoWay
    var id: String { rawValue }
    var title: String { self == .oneWay ? "One-way sync" : "Two-way sync" }
    var symbol: String { self == .oneWay ? "arrow.right" : "arrow.left.arrow.right" }
}

struct SyncPair: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = "Untitled sync"
    var source = ""
    var destination = ""
    var sourceMountPath: String?
    var destinationMountPath: String?
    var sourceVolumeID: String?
    var destinationVolumeID: String?
    // Missing in settings saved before direction selection was introduced.
    var savedDirection: SyncDirection?
    var direction: SyncDirection {
        get { savedDirection ?? .oneWay }
        set { savedDirection = newValue }
    }
    var options = SyncOptions()
    var schedule = SyncSchedule()
    var nextRun: Date?
    var lastRun: Date?
    var lastResult: String?
    var isConfigured: Bool { !source.isEmpty && !destination.isEmpty }
}

struct RunIssue: Identifiable, Codable, Hashable, Sendable {
    enum Reason: String, Codable, Hashable, Sendable {
        case stalled
        case truncatedSource
        case incompleteDestination
        case excludedUncopied

        var label: String {
            switch self {
            case .stalled: "Skipped after transfer stopped making progress"
            case .truncatedSource: "Source read was truncated"
            case .incompleteDestination: "Shorter destination copy was skipped"
            case .excludedUncopied: "Excluded from this sync; destination copy is missing or shorter"
            }
        }
    }

    var path: String
    var reasons: Set<Reason>
    var id: String { path }

    static func fromLog(_ log: String) -> [RunIssue] {
        var issues: [RunIssue] = []
        for line in log.components(separatedBy: .newlines) {
            guard let issue = parse(line) else { continue }
            if let index = issues.firstIndex(where: { $0.path == issue.path }) {
                issues[index].reasons.formUnion(issue.reasons)
            } else {
                issues.append(issue)
            }
        }
        return issues
    }

    static func merging(_ issues: [RunIssue]) -> [RunIssue] {
        var merged: [RunIssue] = []
        for issue in issues {
            if let index = merged.firstIndex(where: { $0.path == issue.path }) {
                merged[index].reasons.formUnion(issue.reasons)
            } else {
                merged.append(issue)
            }
        }
        return merged
    }

    // Only literal, relative file exclusions can identify a precise uncopied path.
    // Patterns and intentionally excluded files already present at the destination
    // are not reported as transfer errors.
    static func excludedUncopied(for pair: SyncPair, command: String? = nil) -> [RunIssue] {
        let sourceRoot = RsyncCommand.url(for: pair.source).path
        let destinationRoot = RsyncCommand.url(for: pair.destination).path
        let issues: [RunIssue] = pair.options.excludePatterns.components(separatedBy: .newlines).compactMap { pattern in
            let path = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
            guard path.contains("/"), !path.contains(where: { "*?[]\\".contains($0) }),
                  let source = RsyncCommand.safeChild(path, of: sourceRoot),
                  let destination = RsyncCommand.safeChild(path, of: destinationRoot) else { return nil }
            if let command {
                let quoted = "'--exclude=" + pattern.replacingOccurrences(of: "'", with: "'\\''") + "'"
                guard command.contains(quoted) else { return nil }
            }
            var sourceInfo = stat()
            guard stat(source, &sourceInfo) == 0, sourceInfo.st_mode & S_IFMT == S_IFREG else { return nil }
            var destinationInfo = stat()
            if stat(destination, &destinationInfo) == 0 {
                guard destinationInfo.st_mode & S_IFMT != S_IFREG || destinationInfo.st_size < sourceInfo.st_size else { return nil }
            } else {
                guard errno == ENOENT else { return nil }
            }
            return RunIssue(path: path, reasons: [.excludedUncopied])
        }
        return merging(issues)
    }

    static func parse(_ line: String) -> RunIssue? {
        if line.hasPrefix("Skipped stalled file after "),
           let separator = line.range(of: " seconds without byte progress: ") {
            return RunIssue(path: String(line[separator.upperBound...]), reasons: [.stalled])
        }
        let incomplete = "Incomplete newer destination skipped by --update: "
        if line.hasPrefix(incomplete) {
            return RunIssue(path: String(line.dropFirst(incomplete.count)), reasons: [.incompleteDestination])
        }
        let truncated = ": file truncated while reading"
        if line.hasSuffix(truncated), let warning = line.range(of: ": warning: ") {
            let path = line[warning.upperBound..<line.index(line.endIndex, offsetBy: -truncated.count)]
            return RunIssue(path: String(path), reasons: [.truncatedSource])
        }
        return nil
    }
}

struct RunRecord: Identifiable, Codable {
    var id = UUID()
    var pairID: UUID
    var pairName: String
    var startedAt: Date
    var finishedAt: Date
    var preview: Bool
    var exitCode: Int32
    var cancelled: Bool
    var logPath: String
    // Nil in records saved before the issue report was added.
    var issues: [RunIssue]? = nil
    var reportedIssues: [RunIssue] { issues ?? [] }
    var succeeded: Bool { exitCode == 0 && !cancelled }
    var title: String { cancelled ? "Cancelled" : succeeded ? (preview ? "Preview complete" : "Sync complete") : "Needs attention" }
    var durationLabel: String {
        let totalSeconds = max(0, Int(finishedAt.timeIntervalSince(startedAt)))
        guard totalSeconds >= 60 else { return "\(totalSeconds.formatted())s" }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return seconds == 0 ? "\(minutes.formatted())m" : "\(minutes.formatted())m \(seconds)s"
    }
}

struct PersistedState: Codable {
    var version = 1
    var pairs: [SyncPair]
    var history: [RunRecord]
}

/// Uses the starting layout so animated rows cannot shift drag thresholds.
enum SyncReorder {
    static func destination(for center: CGFloat, slotCenters: [CGFloat]) -> Int? {
        slotCenters.indices.min { abs(slotCenters[$0] - center) < abs(slotCenters[$1] - center) }
    }
}
