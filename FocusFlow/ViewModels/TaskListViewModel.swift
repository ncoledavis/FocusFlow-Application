import Foundation
import Combine

/// Subscribes to a user's tasks and exposes them sorted for display, plus the
/// add / update / delete actions the task list UI needs.
@MainActor
final class TaskListViewModel: ObservableObject {

    /// Every task for the owner, as last emitted by the repository.
    @Published private(set) var allTasks: [TaskItem] = []

    /// True until the first snapshot (or error) arrives.
    @Published private(set) var isLoading = true

    @Published var errorMessage: String?

    let ownerUid: String

    private let repository: TaskRepository
    private let currentUid: String
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - ownerUid: Whose task list this is.
    ///   - currentUid: Who is acting. Defaults to the owner; a supporter
    ///     editing someone else's list passes their own UID (Task 6).
    init(repository: TaskRepository, ownerUid: String, currentUid: String? = nil) {
        self.repository = repository
        self.ownerUid = ownerUid
        self.currentUid = currentUid ?? ownerUid
    }

    // MARK: - Derived lists

    /// Pending / current tasks, highest priority first.
    var activeTasks: [TaskItem] {
        Self.sorted(allTasks.filter { $0.status.isActive })
    }

    /// Done / skipped tasks, same ordering.
    var finishedTasks: [TaskItem] {
        Self.sorted(allTasks.filter { !$0.status.isActive })
    }

    /// Highest priority first, then manual `order`, then oldest first. The ID
    /// is a final tiebreaker so the result is deterministic.
    static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Subscription

    /// Starts listening to the repository. Safe to call more than once.
    func start() {
        guard cancellable == nil else { return }
        isLoading = true

        cancellable = repository.observeTasks(forOwner: ownerUid)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let error) = completion {
                        self.errorMessage = ErrorMessage.forRepository(error)
                    }
                    self.isLoading = false
                },
                receiveValue: { [weak self] tasks in
                    self?.allTasks = tasks
                    self?.isLoading = false
                }
            )
    }

    // MARK: - Actions

    /// How a new task is scheduled (hybrid model).
    enum NewTaskSchedule: Equatable {
        /// A time budget. The clock starts when the task becomes current.
        case duration(minutes: Int)
        /// A fixed slot with an explicit start and finish.
        case fixed(start: Date, finish: Date)
    }

    /// Validates and creates a new task. Returns true on success.
    @discardableResult
    func addTask(
        title: String,
        notes: String = "",
        priority: Priority = .medium,
        schedule: NewTaskSchedule
    ) async -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Give your task a title."
            return false
        }

        var task = TaskItem(
            id: UUID().uuidString,
            ownerUid: ownerUid,
            title: trimmedTitle,
            notes: Self.normalizedNotes(notes),
            priority: priority,
            createdBy: currentUid,
            order: nextOrder()
        )

        switch schedule {
        case .duration(let minutes):
            guard minutes > 0 else {
                errorMessage = "Time allotted must be at least 1 minute."
                return false
            }
            task.scheduleType = .duration
            task.durationMinutes = minutes
        case .fixed(let start, let finish):
            guard finish > start else {
                errorMessage = "The finish time must be after the start time."
                return false
            }
            task.scheduleType = .fixed
            task.startAt = start
            task.storedTargetFinishAt = finish
        }

        return await perform { try await self.repository.create(task) }
    }

    @discardableResult
    func update(_ task: TaskItem) async -> Bool {
        await perform { try await self.repository.update(task) }
    }

    @discardableResult
    func setPriority(_ priority: Priority, for task: TaskItem) async -> Bool {
        var changed = task
        changed.priority = priority
        return await update(changed)
    }

    @discardableResult
    func delete(_ task: TaskItem) async -> Bool {
        await perform { try await self.repository.delete(taskId: task.id) }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    /// New tasks go after every existing one so they land last within their
    /// priority.
    private func nextOrder() -> Int {
        (allTasks.map(\.order).max() ?? -1) + 1
    }

    private static func normalizedNotes(_ notes: String) -> String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func perform(_ work: () async throws -> Void) async -> Bool {
        errorMessage = nil
        do {
            try await work()
            return true
        } catch {
            errorMessage = ErrorMessage.forRepository(error)
            return false
        }
    }
}
