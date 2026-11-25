import Foundation

/// What the person looking at a task list is allowed to do with it. The owner
/// can do everything; a supporter is limited by the permission the owner gave.
///
/// These checks keep the UI honest and give clear messages. The real
/// enforcement is the Firestore security rules.
enum TaskListAccess: Equatable {
    case owner
    case supporter(LinkPermission)

    var isSupporter: Bool {
        if case .supporter = self { return true }
        return false
    }

    /// Create new tasks. Owner, or a supporter with "add" or "edit".
    var canAdd: Bool {
        switch self {
        case .owner: return true
        case .supporter(let permission): return permission.canAdd
        }
    }

    /// Change a task's priority and order. Owner, or a supporter with "edit".
    var canReorder: Bool {
        switch self {
        case .owner: return true
        case .supporter(let permission): return permission.canEdit
        }
    }

    /// Change anything else about a task, or delete it. Owner only.
    var canModify: Bool {
        self == .owner
    }

    /// A short description for the screen, e.g. "You can add tasks".
    var roleDescription: String {
        switch self {
        case .owner: return "Your tasks"
        case .supporter(.view): return "View only"
        case .supporter(.add): return "You can add tasks"
        case .supporter(.edit): return "You can add tasks and change priority and order"
        }
    }
}
