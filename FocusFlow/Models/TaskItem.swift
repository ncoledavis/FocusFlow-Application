import Foundation

/// A single to-do item. Mirrors `tasks/{taskId}` in Firestore.
///
/// Scheduling is hybrid:
/// - `.duration`: the task has an allotted `durationMinutes`. `startAt` is set
///   when the task becomes current, and the target finish is derived from it.
/// - `.fixed`: the task occupies a fixed slot defined by `startAt` and an
///   explicit `targetFinishAt`.
struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var ownerUid: String
    var title: String
    var notes: String?

    var priority: Priority
    var scheduleType: ScheduleType

    /// Allotted minutes for a `.duration` task. Nil for `.fixed` tasks.
    var durationMinutes: Int?

    /// When the task starts. For `.duration` tasks this is set once the task
    /// becomes current; for `.fixed` tasks it defines the slot start.
    var startAt: Date?

    /// Stored finish time. Primarily meaningful for `.fixed` tasks, or when a
    /// `.duration` task's finish has been extended ("add more time").
    var storedTargetFinishAt: Date?

    var status: TaskStatus

    /// UID of the account that created this task (owner or a supporter).
    var createdBy: String

    /// Manual ordering hint for reordering within the same priority.
    var order: Int

    var createdAt: Date

    init(
        id: String,
        ownerUid: String,
        title: String,
        notes: String? = nil,
        priority: Priority = .medium,
        scheduleType: ScheduleType = .duration,
        durationMinutes: Int? = nil,
        startAt: Date? = nil,
        storedTargetFinishAt: Date? = nil,
        status: TaskStatus = .pending,
        createdBy: String,
        order: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerUid = ownerUid
        self.title = title
        self.notes = notes
        self.priority = priority
        self.scheduleType = scheduleType
        self.durationMinutes = durationMinutes
        self.startAt = startAt
        self.storedTargetFinishAt = storedTargetFinishAt
        self.status = status
        self.createdBy = createdBy
        self.order = order
        self.createdAt = createdAt
    }
}

// MARK: - Computed time model

extension TaskItem {
    /// The effective target finish time for the task.
    ///
    /// Resolution order:
    /// 1. An explicitly stored finish (fixed slot, or an extended duration task).
    /// 2. For `.duration` tasks: `startAt + durationMinutes`.
    /// 3. Otherwise unknown (nil) — e.g. a duration task that hasn't started.
    var targetFinishAt: Date? {
        if let stored = storedTargetFinishAt {
            return stored
        }
        if scheduleType == .duration,
           let start = startAt,
           let minutes = durationMinutes {
            return start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        return nil
    }

    /// Seconds remaining until the target finish, relative to `now`.
    /// Positive while time is left, negative once overdue, nil if no finish
    /// time can be resolved.
    func timeRemaining(asOf now: Date = Date()) -> TimeInterval? {
        guard let finish = targetFinishAt else { return nil }
        return finish.timeIntervalSince(now)
    }

    /// Whether the task's time budget has elapsed without completion.
    func isOverdue(asOf now: Date = Date()) -> Bool {
        guard status.isActive, let remaining = timeRemaining(asOf: now) else {
            return false
        }
        return remaining <= 0
    }
}
