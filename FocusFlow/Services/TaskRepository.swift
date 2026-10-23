import Foundation
import Combine

/// Persistence boundary for tasks. Concrete implementation
/// (FirestoreTaskRepository) arrives in Task 3.
protocol TaskRepository {
    func create(_ task: TaskItem) async throws
    func update(_ task: TaskItem) async throws
    func delete(taskId: String) async throws

    /// Real-time stream of the owner's tasks.
    func observeTasks(forOwner ownerUid: String) -> AnyPublisher<[TaskItem], Error>
}
