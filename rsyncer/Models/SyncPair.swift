import Foundation

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
