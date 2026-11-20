import Foundation
import Combine

/// Drives the one-at-a-time focus screen: picks the task to show, starts its
/// clock, exposes the countdown math, watches for the time running out, keeps
/// the "time's up" notification in step, and handles Done, Skip and "add more
/// time".
@MainActor
final class FocusViewModel: ObservableObject {

    /// Choices offered by the "add more time" prompt, in minutes.
    static let extensionOptions = [5, 10, 15, 30]

    /// Ticks once a second. Injected so tests can drive expiry by hand.
    static let everySecond: AnyPublisher<Void, Never> = Timer
        .publish(every: 1, on: .main, in: .common)
        .autoconnect()
        .map { _ in () }
        .eraseToAnyPublisher()

    /// Every task for the owner, as last emitted by the repository.
    @Published private(set) var allTasks: [TaskItem] = []

    /// True until the first snapshot (or error) arrives.
    @Published private(set) var isLoading = true

    /// True while a Done, Skip or add-time write is in flight, so the buttons
    /// can't double-fire.
    @Published private(set) var isWorking = false

    /// True once the current task's countdown has reached zero. Drives the
    /// "Still working on this?" prompt.
    @Published private(set) var isOverdue = false

    /// Whether "time's up" notifications can be delivered. `.denied` means the
    /// user only gets the in-app prompt.
    @Published private(set) var notificationPermission: NotificationPermission = .notDetermined

    @Published var errorMessage: String?

    let ownerUid: String

    private let repository: TaskRepository
    private let notifications: NotificationService
    private let clock: () -> Date
    private let ticker: AnyPublisher<Void, Never>
    private var cancellable: AnyCancellable?
    private var tickCancellable: AnyCancellable?
    private var promotingTaskId: String?

    /// The expiry notification currently scheduled, so it's only rescheduled
    /// when the task or its finish time actually changes.
    private var scheduledExpiry: (taskId: String, finish: Date)?

    /// The in-flight write that starts the current task. Exposed so tests (and
    /// Done / Skip) can wait for the next task to be started.
    private(set) var promotionTask: Task<Void, Never>?

    /// The in-flight permission check, exposed for tests.
    private(set) var permissionTask: Task<Void, Never>?

    /// - Parameters:
    ///   - clock: The time source. Tests inject a fixed clock.
    ///   - ticker: Fires once a second to check whether time has run out.
    ///     Tests inject a subject they control.
    init(
        repository: TaskRepository,
        ownerUid: String,
        notificationService: NotificationService,
        clock: @escaping () -> Date = Date.init,
        ticker: AnyPublisher<Void, Never> = FocusViewModel.everySecond
    ) {
        self.repository = repository
        self.ownerUid = ownerUid
        self.notifications = notificationService
        self.clock = clock
        self.ticker = ticker
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

    /// Starts listening to the repository, begins watching for expiry, and
    /// asks for notification permission. Safe to call more than once.
    func start() {
        guard cancellable == nil else { return }
        isLoading = true
        refreshNotificationPermission()

        tickCancellable = ticker.sink { [weak self] _ in
            guard let self else { return }
            self.checkExpiry(asOf: self.clock())
        }

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
                    self.checkExpiry(asOf: self.clock())
                    self.syncExpiryNotification()
                }
            )
    }

    /// Re-reads the notification permission, asking if the user hasn't been
    /// asked yet. Called at start and when the app returns to the foreground,
    /// so turning notifications on in Settings is picked up.
    func refreshNotificationPermission() {
        permissionTask = Task { [weak self] in
            guard let self else { return }
            self.notificationPermission = await self.notifications.requestPermissionIfNeeded()
        }
    }

    // MARK: - Expiry (5.3)

    /// Sets `isOverdue` from the current task's countdown. Driven by the
    /// one-second ticker and by every list update.
    func checkExpiry(asOf now: Date) {
        let overdue = currentTask?.isOverdue(asOf: now) ?? false
        // Only assign on change so the screen isn't invalidated every second.
        if overdue != isOverdue {
            isOverdue = overdue
        }
    }

    // MARK: - Actions

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

    /// "Still working": pushes the current task's finish out by `minutes`,
    /// counted from now if time has already run out. The repository re-emits
    /// the list, which clears the overdue state and reschedules the
    /// notification.
    @discardableResult
    func addMoreTime(minutes: Int) async -> Bool {
        guard minutes > 0, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        await promotionTask?.value
        guard let task = currentTask else { return false }
        return await write(task.extended(byMinutes: minutes, from: clock()))
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

    /// Keeps one "time's up" notification scheduled for the running task, at
    /// its finish time. Reschedules when the finish changes (add more time) and
    /// cancels when the task changes or finishes (Done, Skip) or the time has
    /// already passed.
    private func syncExpiryNotification() {
        guard let task = currentTask,
              task.status == .current,
              let finish = task.targetFinishAt,
              finish > clock() else {
            cancelScheduledExpiry()
            return
        }

        if let scheduled = scheduledExpiry {
            if scheduled.taskId == task.id, scheduled.finish == finish { return }
            if scheduled.taskId != task.id {
                notifications.cancelExpiry(forTaskId: scheduled.taskId)
            }
        }
        notifications.scheduleExpiry(for: task, at: finish)
        scheduledExpiry = (task.id, finish)
    }

    private func cancelScheduledExpiry() {
        guard let scheduled = scheduledExpiry else { return }
        notifications.cancelExpiry(forTaskId: scheduled.taskId)
        scheduledExpiry = nil
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

        // The repository re-emits the list, which cancels this task's
        // notification and starts the next task. Wait for that so the next
        // card appears already running.
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
