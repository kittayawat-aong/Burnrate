import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter for local notifications.
enum NotificationService {
    /// Request permission up front (e.g. at launch) so the first real alert
    /// isn't swallowed by the permission prompt.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                LogService.shared.log(.warning, .notification, "\"\(title)\" not sent — notifications not authorized")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
            LogService.shared.log(.info, .notification, "Sent \"\(title)\": \(body)")
        }
    }
}
