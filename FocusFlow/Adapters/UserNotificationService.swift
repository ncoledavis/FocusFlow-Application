import Foundation
import UserNotifications

/// `NotificationService` backed by `UNUserNotificationCenter`.
///
/// Local notifications need no Info.plist key. The app doesn't present
/// notifications while it's in the foreground (there's no delegate); in that
/// case the in-app "time's up" prompt is the alert.
final class UserNotificationService: NotificationService {

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestPermissionIfNeeded() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            return granted ? .granted : .denied
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func scheduleExpiry(for task: TaskItem, at date: Date) {
        guard let request = Self.makeRequest(taskId: task.id, title: task.title, at: date, now: Date()) else {
            return
        }
        center.add(request) { error in
            #if DEBUG
            if let error {
                print("[UserNotificationService] Couldn't schedule notification: \(error)")
            }
            #endif
        }
    }

    func cancelExpiry(forTaskId taskId: String) {
        let identifiers = [Self.identifier(for: taskId)]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Request building

    /// One identifier per task, so rescheduling replaces the earlier request.
    static func identifier(for taskId: String) -> String {
        "task-expiry-\(taskId)"
    }

    /// Builds the notification request, or nil if `date` isn't in the future
    /// (a time-interval trigger must be greater than zero).
    static func makeRequest(taskId: String, title: String, at date: Date, now: Date) -> UNNotificationRequest? {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "\"\(title)\" has run out of time. Still working on it?"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: identifier(for: taskId), content: content, trigger: trigger)
    }
}
