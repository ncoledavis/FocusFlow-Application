import Foundation

/// Records notification calls instead of posting them. Used by tests and
/// previews.
final class MockNotificationService: NotificationService {

    struct ScheduledNotification: Equatable {
        let taskId: String
        let title: String
        let date: Date
    }

    /// What `requestPermissionIfNeeded` returns.
    var permission: NotificationPermission

    private(set) var permissionRequestCount = 0
    private(set) var scheduled: [ScheduledNotification] = []
    private(set) var cancelledTaskIds: [String] = []

    init(permission: NotificationPermission = .granted) {
        self.permission = permission
    }

    func requestPermissionIfNeeded() async -> NotificationPermission {
        permissionRequestCount += 1
        return permission
    }

    func scheduleExpiry(for task: TaskItem, at date: Date) {
        scheduled.append(ScheduledNotification(taskId: task.id, title: task.title, date: date))
    }

    func cancelExpiry(forTaskId taskId: String) {
        cancelledTaskIds.append(taskId)
    }
}
