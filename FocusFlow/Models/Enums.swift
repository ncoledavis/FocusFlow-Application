import Foundation

/// Relative importance of a task. Used to suggest the current one-at-a-time task.
/// `Comparable` so the highest-priority pending task can be selected.
enum Priority: String, Codable, CaseIterable, Comparable, Identifiable {
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    /// Human-facing label.
    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    /// Ordering weight; higher means more important.
    var sortWeight: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }

    static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.sortWeight < rhs.sortWeight
    }
}

/// Lifecycle state of a task.
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case current
    case done
    case skipped

    var id: String { rawValue }

    /// Whether the task is still actionable (eligible to become the current task).
    var isActive: Bool {
        self == .pending || self == .current
    }
}

/// How a task is placed in time. A task either has a flexible duration or a
/// fixed time slot (hybrid scheduling).
enum ScheduleType: String, Codable, CaseIterable, Identifiable {
    case duration
    case fixed

    var id: String { rawValue }
}

/// What a linked supporter is allowed to do with the owner's task list.
/// `Comparable` so permission checks can compare capability levels.
enum LinkPermission: String, Codable, CaseIterable, Comparable, Identifiable {
    case view
    case add
    case edit

    var id: String { rawValue }

    /// Capability level; higher includes the capabilities below it.
    var level: Int {
        switch self {
        case .view: return 0
        case .add: return 1
        case .edit: return 2
        }
    }

    /// Supporter can read the task list.
    var canView: Bool { level >= LinkPermission.view.level }
    /// Supporter can create new tasks.
    var canAdd: Bool { level >= LinkPermission.add.level }
    /// Supporter can modify priority/order of existing tasks.
    var canEdit: Bool { level >= LinkPermission.edit.level }

    static func < (lhs: LinkPermission, rhs: LinkPermission) -> Bool {
        lhs.level < rhs.level
    }
}

/// Lifecycle state of a supporter link.
enum LinkStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case active

    var id: String { rawValue }
}
