import AppKit
import Combine
import Foundation

struct GitHubRelease: Decodable {
    let tagName: String
    let pageURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
    }
}

enum AppVersion {
    static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first?.lowercased() == "v" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = components(candidate), let current = components(current) else { return false }
        for index in 0..<max(candidate.count, current.count) {
            let candidatePart = index < candidate.count ? candidate[index] : 0
            let currentPart = index < current.count ? current[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let normalized = normalized(version)
        let stable = normalized.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let fields = stable.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty else { return nil }

        var result: [Int] = []
        for field in fields {
            guard !field.isEmpty, let value = Int(field), value >= 0 else { return nil }
            result.append(value)
        }
        return result
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/ludehon/rsyncer/releases/latest")!
    private static let lastCheckKey = "updateChecker.lastSuccessfulCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersion: String
    private var isChecking = false

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    ) {
        self.session = session
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    func checkForUpdatesIfNeeded(now: Date = Date()) async {
        guard !isChecking, shouldCheck(at: now) else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Rsyncer/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            defaults.set(now, forKey: Self.lastCheckKey)
            guard AppVersion.isNewer(release.tagName, than: currentVersion) else { return }
            presentUpdate(release)
        } catch {
            // Automatic update checks must never interrupt app startup.
        }
    }

    private func shouldCheck(at now: Date) -> Bool {
        guard let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= Self.checkInterval
    }

    private func presentUpdate(_ release: GitHubRelease) {
        let version = AppVersion.normalized(release.tagName)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Rsyncer \(version) is available"
        alert.informativeText = "You’re using Rsyncer \(currentVersion). Open the GitHub release to download the update."
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }
}
