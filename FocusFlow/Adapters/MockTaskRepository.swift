import Foundation
import Combine

/// In-memory `TaskRepository` for previews, tests, and running the app before
/// Firebase is configured. Mirrors Firestore's behavior of re-emitting the
/// owner's full task list on every change.
final class MockTaskRepository: TaskRepository {

    private let store: CurrentValueSubject<[String: TaskItem], Never>

    /// When set, the next write throws this error instead of succeeding.
    var nextError: Error?

    /// When set, `observeTasks` fails immediately with this error.
    var observeError: Error?

    init(initialTasks: [TaskItem] = []) {
        store = CurrentValueSubject(Dictionary(uniqueKeysWithValues: initialTasks.map { ($0.id, $0) }))
    }

    func create(_ task: TaskItem) async throws {
        try throwPendingError()
        store.value[task.id] = task
    }

    func update(_ task: TaskItem) async throws {
        try throwPendingError()
        guard store.value[task.id] != nil else { throw TaskRepositoryError.notFound }
        store.value[task.id] = task
    }

    func delete(taskId: String) async throws {
        try throwPendingError()
        guard store.value[taskId] != nil else { throw TaskRepositoryError.notFound }
        store.value[taskId] = nil
    }

    func observeTasks(forOwner ownerUid: String) -> AnyPublisher<[TaskItem], Error> {
        if let observeError {
            return Fail(error: observeError).eraseToAnyPublisher()
        }
        return store
            .map { tasks in tasks.values.filter { $0.ownerUid == ownerUid } }
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    private func throwPendingError() throws {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
    }
}
