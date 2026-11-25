import Foundation
import Combine

/// Errors raised by `TaskRepository` implementations.
enum TaskRepositoryError: LocalizedError, Equatable {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "That task no longer exists."
        }
    }
}

/// Persistence boundary for tasks. Implemented by `FirestoreTaskRepository` in
/// production and `MockTaskRepository` for previews, tests, and offline demos.
protocol TaskRepository {
    /// Creates the task. The task's `id` is used as the document ID.
    func create(_ task: TaskItem) async throws

    /// Replaces the stored task with the given value.
    func update(_ task: TaskItem) async throws

    func delete(taskId: String) async throws

    /// Changes only `priority` and `order`, leaving every other field alone.
    /// This is the one change a supporter with "edit" permission may make, and
    /// it avoids overwriting a status change made at the same moment.
    func updateOrdering(taskId: String, priority: Priority, order: Int) async throws

    /// Real-time stream of the owner's tasks, in no guaranteed order.
    /// Emits the full list on every change. Callers sort for display, and
    /// values must be delivered on the main queue.
    func observeTasks(forOwner ownerUid: String) -> AnyPublisher<[TaskItem], Error>
}
