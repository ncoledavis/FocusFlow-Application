import Foundation

/// Whether the app may post notifications.
enum NotificationPermission: Equatable {
    /// The user hasn't been asked yet.
    case notDetermined
    case granted
    /// The user said no (or turned notifications off in Settings).
    case denied
}

/// Boundary for the "time's up" local notification. Implemented by
/// `UserNotificationService` in production and `MockNotificationService` in
/// tests.
///
/// Scheduling and cancelling are synchronous so calls are applied in the order
/// they're made (a cancel can't overtake an earlier schedule).
protocol NotificationService {
    /// Asks for permission if the user hasn't been asked yet, and returns the
    /// resulting state. Safe to call repeatedly; the system only prompts once.
    func requestPermissionIfNeeded() async -> NotificationPermission

    /// Schedules the expiry notification for a task, replacing any earlier one
    /// for the same task.
    func scheduleExpiry(for task: TaskItem, at date: Date)

    /// Removes a task's pending and delivered expiry notifications.
    func cancelExpiry(forTaskId taskId: String)
}
