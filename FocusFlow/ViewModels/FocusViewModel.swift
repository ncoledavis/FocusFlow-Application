import Foundation
import Combine

/// Drives the one-at-a-time focus screen: picks the task to show, starts its
/// clock, exposes the countdown math, and handles Done and Skip.
@MainActor
final class FocusViewModel: ObservableObject {

    /// Every task for the owner, as last emitted by the repository.
    @Published private(set) var allTasks: [TaskItem] = []

    /// True until the first snapshot (or error) arrives.
    @Published private(set) var isLoading = true

    /// True while a Done or Skip is in flight, so the buttons can't double-fire.
    @Published private(set) var isWorking = false

    @Published var errorMessage: String?

    let ownerUid: String

    private let repository: TaskRepository
    private let clock: () -> Date
    private var cancellable: AnyCancellable?
    private var promotingTaskId: String?

    /// The in-flight write that starts the current task. Exposed so tests (and
    /// Done / Skip) can wait for the next task to be started.
    private(set) var promotionTask: Task<Void, Never>?

    /// - Parameter clock: The time source. Tests inject a fixed clock.
    init(repository: TaskRepository, ownerUid: String, clock: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.ownerUid = ownerUid
        self.clock = clock
    }

    // MARK: - Current-task selection (4.1)

    /// The task to focus on right now.
    var currentTask: TaskItem? {
        Self.selectCurrent(from: allTasks)
    }

    /// How many active tasks are waiting behind the current one.
    var upNextCount: Int {
        max(allTasks.filter { $0.status.isActive }.count - 1, 0)
    }

    /// Picks the task to focus on. A task already marked `current` wins, so a
    /// newly added high-priority task doesn't yank the user away mid-task.
    /// Otherwise it's the highest-priority pending task: priority is a strong
    /// suggestion, then manual order, then oldest first.
    static func selectCurrent(from tasks: [TaskItem]) -> TaskItem? {
        let active = TaskListViewModel.sorted(tasks.filter { $0.status.isActive })
        return active.first { $0.status == .current } ?? active.first
    }

    // MARK: - Time model (4.3)

    /// Seconds left on the current task. Positive while time remains, zero or
    /// negative once it runs out. For a task whose clock hasn't started this is
    /// the full allotment.
    func displayRemaining(asOf date: Date) -> TimeInterval? {
        guard let task = currentTask else { return nil }
        return task.timeRemaining(asOf: date) ?? task.allottedInterval
    }

    /// Fraction of the allotted time still left (1 = all of it, 0 = none),
    /// clamped to 0...1. Drives the countdown ring.
    func remainingFraction(asOf date: Date) -> Double? {
        guard let task = currentTask,
              let total = task.allottedInterval, total > 0,
              let remaining = displayRemaining(asOf: date) else { return nil }
        return min(max(remaining / total, 0), 1)
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
                    guard let self else { return }
                    self.allTasks = tasks
                    self.isLoading = false
                    self.startCurrentIfNeeded()
                }
            )
    }

    // MARK: - Actions (4.5, 4.6)

    /// Marks the current task done and advances to the next one.
    @discardableResult
    func markDone() async -> Bool {
        await finishCurrent(as: .done)
    }

    /// Marks the current task skipped and advances to the next one.
    @discardableResult
    func skip() async -> Bool {
        await finishCurrent(as: .skipped)
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    /// Moves the current task from pending to current and, for duration tasks,
    /// stamps `startAt` so the countdown is stored and survives relaunch.
    private func startCurrentIfNeeded() {
        guard let task = currentTask,
              task.status == .pending,
              promotingTaskId != task.id else { return }

        promotingTaskId = task.id
        var started = task
        started.status = .current
        if started.scheduleType == .duration, started.startAt == nil {
            started.startAt = clock()
        }

        promotionTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.write(started)
            self.promotingTaskId = nil
        }
    }

    private func finishCurrent(as status: TaskStatus) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        // Let any in-flight start settle so we act on the stored state.
        await promotionTask?.value
        guard var task = currentTask else { return false }

        task.status = status
        guard await write(task) else { return false }

        // The repository re-emits the list, which starts the next task. Wait
        // for that so the next card appears already running.
        await promotionTask?.value
        return true
    }

    private func write(_ task: TaskItem) async -> Bool {
        do {
            try await repository.update(task)
            return true
        } catch {
            errorMessage = ErrorMessage.forRepository(error)
            return false
        }
    }
}
