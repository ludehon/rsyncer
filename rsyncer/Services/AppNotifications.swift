import Foundation
import UserNotifications

enum AppNotifications {
    static func requestAuthorization() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func send(title: String, body: String, identifier: String = UUID().uuidString) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}
