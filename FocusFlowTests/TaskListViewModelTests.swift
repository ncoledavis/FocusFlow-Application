import XCTest
@testable import FocusFlow

@MainActor
final class TaskListViewModelTests: XCTestCase {

    private let owner = "owner-1"

    private func makeTask(
        _ id: String,
        title: String = "Task",
        owner: String = "owner-1",
        priority: Priority = .medium,
        status: TaskStatus = .pending,
        order: Int = 0,
        createdAt: TimeInterval = 1_000
    ) -> TaskItem {
        TaskItem(
            id: id,
            ownerUid: owner,
            title: title,
            priority: priority,
            durationMinutes: 25,
            status: status,
            createdBy: owner,
            order: order,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func makeViewModel(
        tasks: [TaskItem] = [],
        repository: MockTaskRepository? = nil
    ) -> (TaskListViewModel, MockTaskRepository) {
        let repo = repository ?? MockTaskRepository(initialTasks: tasks)
        let viewModel = TaskListViewModel(repository: repo, ownerUid: owner)
        viewModel.start()
        return (viewModel, repo)
    }

    // MARK: - Subscription

    func testStartLoadsOnlyTheOwnersTasks() {
        let (viewModel, _) = makeViewModel(tasks: [
            makeTask("mine"),
            makeTask("theirs", owner: "someone-else")
        ])

        XCTAssertEqual(viewModel.allTasks.map(\.id), ["mine"])
        XCTAssertFalse(viewModel.isLoading)
    }

    func testIsLoadingUntilStarted() {
        let viewModel = TaskListViewModel(repository: MockTaskRepository(), ownerUid: owner)
        XCTAssertTrue(viewModel.isLoading)

        viewModel.start()
        XCTAssertFalse(viewModel.isLoading)
    }

    func testObservationFailureSurfacesErrorAndStopsLoading() {
        struct StreamError: LocalizedError { var errorDescription: String? { "stream broke" } }
        let repo = MockTaskRepository()
        repo.observeError = StreamError()

        let (viewModel, _) = makeViewModel(repository: repo)

        XCTAssertEqual(viewModel.errorMessage, "stream broke")
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Ordering

    func testActiveTasksSortByPriorityThenOrderThenCreatedAt() {
        let (viewModel, _) = makeViewModel(tasks: [
            makeTask("low", priority: .low),
            makeTask("urgent", priority: .urgent),
            makeTask("high-late", priority: .high, order: 2),
            makeTask("high-early", priority: .high, order: 1),
            makeTask("medium-b", priority: .medium, order: 0, createdAt: 2_000),
            makeTask("medium-a", priority: .medium, order: 0, createdAt: 1_000)
        ])

        XCTAssertEqual(
            viewModel.activeTasks.map(\.id),
            ["urgent", "high-early", "high-late", "medium-a", "medium-b", "low"]
        )
    }

    func testFinishedTasksAreSeparatedFromActive() {
        let (viewModel, _) = makeViewModel(tasks: [
            makeTask("pending", status: .pending),
            makeTask("current", status: .current),
            makeTask("done", status: .done),
            makeTask("skipped", status: .skipped)
        ])

        XCTAssertEqual(Set(viewModel.activeTasks.map(\.id)), ["pending", "current"])
        XCTAssertEqual(Set(viewModel.finishedTasks.map(\.id)), ["done", "skipped"])
    }

    // MARK: - Add

    func testAddTaskAppearsInLiveList() async {
        let (viewModel, _) = makeViewModel()

        let succeeded = await viewModel.addTask(
            title: "  Write report  ",
            notes: "  Section 2  ",
            priority: .high,
            schedule: .duration(minutes: 45)
        )

        XCTAssertTrue(succeeded)
        XCTAssertNil(viewModel.errorMessage)
        let task = try? XCTUnwrap(viewModel.activeTasks.first)
        XCTAssertEqual(task?.title, "Write report")
        XCTAssertEqual(task?.notes, "Section 2")
        XCTAssertEqual(task?.priority, .high)
        XCTAssertEqual(task?.durationMinutes, 45)
        XCTAssertEqual(task?.scheduleType, .duration)
        XCTAssertEqual(task?.status, .pending)
        XCTAssertEqual(task?.ownerUid, owner)
        XCTAssertEqual(task?.createdBy, owner)
    }

    func testAddTaskWithBlankNotesStoresNil() async {
        let (viewModel, _) = makeViewModel()

        await viewModel.addTask(title: "Task", notes: "   ", schedule: .duration(minutes: 10))

        XCTAssertNil(viewModel.allTasks.first?.notes)
    }

    func testNewTasksGoAfterExistingOnesWithinPriority() async {
        let (viewModel, _) = makeViewModel(tasks: [makeTask("existing", order: 4)])

        await viewModel.addTask(title: "Newer", priority: .medium, schedule: .duration(minutes: 10))

        XCTAssertEqual(viewModel.activeTasks.last?.title, "Newer")
        XCTAssertEqual(viewModel.activeTasks.last?.order, 5)
    }

    func testAddTaskRejectsBlankTitle() async {
        let (viewModel, _) = makeViewModel()

        let succeeded = await viewModel.addTask(title: "   ", schedule: .duration(minutes: 10))

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, "Give your task a title.")
        XCTAssertTrue(viewModel.allTasks.isEmpty)
    }

    func testAddTaskRejectsZeroDuration() async {
        let (viewModel, _) = makeViewModel()

        let succeeded = await viewModel.addTask(title: "Task", schedule: .duration(minutes: 0))

        XCTAssertFalse(succeeded)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.allTasks.isEmpty)
    }

    func testAddTaskSurfacesRepositoryError() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        let (viewModel, repo) = makeViewModel()
        repo.nextError = WriteError()

        let succeeded = await viewModel.addTask(title: "Task", schedule: .duration(minutes: 10))

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, "write failed")
        XCTAssertTrue(viewModel.allTasks.isEmpty)
    }

    func testSuccessfulActionClearsPreviousError() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.addTask(title: "", schedule: .duration(minutes: 10))
        XCTAssertNotNil(viewModel.errorMessage)

        await viewModel.addTask(title: "Real task", schedule: .duration(minutes: 10))

        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Update

    func testUpdateChangesTask() async {
        let original = makeTask("a", title: "Old")
        let (viewModel, _) = makeViewModel(tasks: [original])

        var edited = original
        edited.title = "New"
        let succeeded = await viewModel.update(edited)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.allTasks.first?.title, "New")
    }

    func testSetPriorityReordersList() async {
        let first = makeTask("first", priority: .high)
        let second = makeTask("second", priority: .low)
        let (viewModel, _) = makeViewModel(tasks: [first, second])
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["first", "second"])

        await viewModel.setPriority(.urgent, for: second)

        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["second", "first"])
    }

    func testUpdateMissingTaskSurfacesNotFound() async {
        let (viewModel, _) = makeViewModel()

        let succeeded = await viewModel.update(makeTask("ghost"))

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, TaskRepositoryError.notFound.errorDescription)
    }

    // MARK: - Delete

    func testDeleteRemovesTask() async {
        let doomed = makeTask("doomed")
        let (viewModel, _) = makeViewModel(tasks: [doomed, makeTask("keeper")])

        let succeeded = await viewModel.delete(doomed)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.allTasks.map(\.id), ["keeper"])
    }

    func testDeleteMissingTaskSurfacesNotFound() async {
        let (viewModel, _) = makeViewModel()

        let succeeded = await viewModel.delete(makeTask("ghost"))

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, TaskRepositoryError.notFound.errorDescription)
    }

    // MARK: - Hybrid schedule (4.4)

    func testAddFixedTaskStoresTheSlot() async throws {
        let (viewModel, _) = makeViewModel()
        let start = Date(timeIntervalSince1970: 2_000_000)
        let finish = start.addingTimeInterval(45 * 60)

        let succeeded = await viewModel.addTask(
            title: "Dentist",
            schedule: .fixed(start: start, finish: finish)
        )

        XCTAssertTrue(succeeded)
        let task = try XCTUnwrap(viewModel.allTasks.first)
        XCTAssertEqual(task.scheduleType, .fixed)
        XCTAssertEqual(task.startAt, start)
        XCTAssertEqual(task.targetFinishAt, finish)
        XCTAssertNil(task.durationMinutes)
        XCTAssertEqual(task.status, .pending)
    }

    func testAddDurationTaskLeavesTheClockUnstarted() async throws {
        let (viewModel, _) = makeViewModel()

        await viewModel.addTask(title: "Write", schedule: .duration(minutes: 20))

        let task = try XCTUnwrap(viewModel.allTasks.first)
        XCTAssertEqual(task.scheduleType, .duration)
        XCTAssertEqual(task.durationMinutes, 20)
        XCTAssertNil(task.startAt)
        XCTAssertNil(task.targetFinishAt)
    }

    func testAddFixedTaskRejectsFinishNotAfterStart() async {
        let (viewModel, _) = makeViewModel()
        let start = Date(timeIntervalSince1970: 2_000_000)

        let sameTime = await viewModel.addTask(title: "Zero length", schedule: .fixed(start: start, finish: start))
        XCTAssertFalse(sameTime)
        XCTAssertEqual(viewModel.errorMessage, "The finish time must be after the start time.")

        let backwards = await viewModel.addTask(
            title: "Backwards",
            schedule: .fixed(start: start, finish: start.addingTimeInterval(-60))
        )
        XCTAssertFalse(backwards)
        XCTAssertTrue(viewModel.allTasks.isEmpty)
    }

    func testClearErrorResetsMessage() async {
        let (viewModel, _) = makeViewModel()
        await viewModel.addTask(title: "", schedule: .duration(minutes: 10))
        XCTAssertNotNil(viewModel.errorMessage)

        viewModel.clearError()

        XCTAssertNil(viewModel.errorMessage)
    }
}
