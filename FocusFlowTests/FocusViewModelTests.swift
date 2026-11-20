import XCTest
@testable import FocusFlow

@MainActor
final class FocusViewModelTests: XCTestCase {

    private let owner = "owner-1"
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// A clock the test can move forward.
    private final class TestClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func makeTask(
        _ id: String,
        owner: String = "owner-1",
        priority: Priority = .medium,
        status: TaskStatus = .pending,
        order: Int = 0,
        createdAt: TimeInterval = 1_000,
        minutes: Int = 25,
        startAt: Date? = nil
    ) -> TaskItem {
        TaskItem(
            id: id,
            ownerUid: owner,
            title: "Task \(id)",
            priority: priority,
            scheduleType: .duration,
            durationMinutes: minutes,
            startAt: startAt,
            status: status,
            createdBy: owner,
            order: order,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    /// Builds a started view model and waits for the first task to be started.
    private func makeViewModel(
        tasks: [TaskItem] = [],
        clock: TestClock? = nil,
        repository: MockTaskRepository? = nil
    ) async -> (FocusViewModel, MockTaskRepository) {
        let repo = repository ?? MockTaskRepository(initialTasks: tasks)
        let testClock = clock ?? TestClock(base)
        let viewModel = FocusViewModel(
            repository: repo,
            ownerUid: owner,
            clock: { testClock.now }
        )
        viewModel.start()
        await viewModel.promotionTask?.value
        return (viewModel, repo)
    }

    private func stored(_ id: String, in viewModel: FocusViewModel) -> TaskItem? {
        viewModel.allTasks.first { $0.id == id }
    }

    // MARK: - Selection (4.1)

    func testSelectsHighestPriorityPendingTask() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("low", priority: .low),
            makeTask("urgent", priority: .urgent),
            makeTask("medium", priority: .medium)
        ])

        XCTAssertEqual(viewModel.currentTask?.id, "urgent")
    }

    func testSelectionBreaksTiesByOrderThenCreatedAt() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("later-order", priority: .high, order: 1),
            makeTask("first-order-newer", priority: .high, order: 0, createdAt: 2_000),
            makeTask("first-order-older", priority: .high, order: 0, createdAt: 1_000)
        ])

        XCTAssertEqual(viewModel.currentTask?.id, "first-order-older")
    }

    func testTaskAlreadyInProgressWinsOverHigherPriorityPending() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("in-progress", priority: .low, status: .current, startAt: base),
            makeTask("urgent", priority: .urgent)
        ])

        XCTAssertEqual(viewModel.currentTask?.id, "in-progress")
        XCTAssertEqual(stored("urgent", in: viewModel)?.status, .pending, "Urgent task should wait its turn")
    }

    func testIgnoresDoneAndSkippedTasks() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("done", priority: .urgent, status: .done),
            makeTask("skipped", priority: .urgent, status: .skipped),
            makeTask("waiting", priority: .low)
        ])

        XCTAssertEqual(viewModel.currentTask?.id, "waiting")
    }

    func testNoCurrentTaskWhenThereAreNoActiveTasks() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("done", status: .done)
        ])

        XCTAssertNil(viewModel.currentTask)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testOnlyTheOwnersTasksAreConsidered() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("theirs", owner: "someone-else", priority: .urgent),
            makeTask("mine", priority: .low)
        ])

        XCTAssertEqual(viewModel.currentTask?.id, "mine")
    }

    func testUpNextCountExcludesCurrentAndFinishedTasks() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("a", priority: .high),
            makeTask("b"),
            makeTask("c"),
            makeTask("done", status: .done)
        ])

        XCTAssertEqual(viewModel.upNextCount, 2)
    }

    func testNewHigherPriorityTaskDoesNotInterruptCurrentTask() async throws {
        let (viewModel, repo) = await makeViewModel(tasks: [makeTask("working", priority: .low)])
        XCTAssertEqual(viewModel.currentTask?.id, "working")

        try await repo.create(makeTask("urgent", priority: .urgent))
        await viewModel.promotionTask?.value

        XCTAssertEqual(viewModel.currentTask?.id, "working")
        XCTAssertEqual(viewModel.upNextCount, 1)
    }

    // MARK: - Starting the clock

    func testStartingPromotesPendingTaskToCurrentAndStampsStartTime() async {
        let (viewModel, _) = await makeViewModel(tasks: [makeTask("a", minutes: 30)])

        let task = stored("a", in: viewModel)
        XCTAssertEqual(task?.status, .current)
        XCTAssertEqual(task?.startAt, base)
        XCTAssertEqual(task?.targetFinishAt, base.addingTimeInterval(30 * 60))
    }

    func testPromotionLeavesFixedSlotTimesUntouched() async {
        let slotStart = base.addingTimeInterval(3_600)
        let slotFinish = base.addingTimeInterval(5_400)
        let fixed = TaskItem(
            id: "fixed",
            ownerUid: owner,
            title: "Standup",
            scheduleType: .fixed,
            startAt: slotStart,
            storedTargetFinishAt: slotFinish,
            createdBy: owner
        )

        let (viewModel, _) = await makeViewModel(tasks: [fixed])

        let task = stored("fixed", in: viewModel)
        XCTAssertEqual(task?.status, .current)
        XCTAssertEqual(task?.startAt, slotStart)
        XCTAssertEqual(task?.targetFinishAt, slotFinish)
    }

    func testTaskAlreadyInProgressKeepsItsOriginalStartTime() async {
        let originalStart = base.addingTimeInterval(-600)
        let clock = TestClock(base)
        let (viewModel, _) = await makeViewModel(
            tasks: [makeTask("a", status: .current, startAt: originalStart)],
            clock: clock
        )

        XCTAssertEqual(stored("a", in: viewModel)?.startAt, originalStart)
    }

    func testOnlyOneTaskIsStarted() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("a", priority: .high),
            makeTask("b"),
            makeTask("c")
        ])

        XCTAssertEqual(viewModel.allTasks.filter { $0.status == .current }.count, 1)
    }

    func testFailedStartSurfacesErrorAndLeavesTaskPending() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        let repo = MockTaskRepository(initialTasks: [makeTask("a")])
        repo.nextError = WriteError()

        let (viewModel, _) = await makeViewModel(repository: repo)

        XCTAssertEqual(viewModel.errorMessage, "write failed")
        XCTAssertEqual(stored("a", in: viewModel)?.status, .pending)
        XCTAssertNil(stored("a", in: viewModel)?.startAt)
    }

    // MARK: - Time model (4.3)

    func testRemainingCountsDownFromStart() async throws {
        let (viewModel, _) = await makeViewModel(tasks: [makeTask("a", minutes: 10)])

        let early = try XCTUnwrap(viewModel.displayRemaining(asOf: base.addingTimeInterval(4 * 60)))
        XCTAssertEqual(early, 6 * 60, accuracy: 0.001)

        let late = try XCTUnwrap(viewModel.displayRemaining(asOf: base.addingTimeInterval(12 * 60)))
        XCTAssertEqual(late, -2 * 60, accuracy: 0.001, "Overtime shows as negative remaining")
    }

    func testRemainingFractionIsClampedToZeroAndOne() async throws {
        let (viewModel, _) = await makeViewModel(tasks: [makeTask("a", minutes: 10)])

        let atStart = try XCTUnwrap(viewModel.remainingFraction(asOf: base))
        XCTAssertEqual(atStart, 1, accuracy: 0.001)

        let halfway = try XCTUnwrap(viewModel.remainingFraction(asOf: base.addingTimeInterval(5 * 60)))
        XCTAssertEqual(halfway, 0.5, accuracy: 0.001)

        let overtime = try XCTUnwrap(viewModel.remainingFraction(asOf: base.addingTimeInterval(15 * 60)))
        XCTAssertEqual(overtime, 0, accuracy: 0.001)

        let beforeStart = try XCTUnwrap(viewModel.remainingFraction(asOf: base.addingTimeInterval(-60)))
        XCTAssertEqual(beforeStart, 1, accuracy: 0.001)
    }

    func testRemainingIsFullAllotmentWhenClockCouldNotStart() async throws {
        struct WriteError: Error {}
        let repo = MockTaskRepository(initialTasks: [makeTask("a", minutes: 25)])
        repo.nextError = WriteError()
        let (viewModel, _) = await makeViewModel(repository: repo)

        let remaining = try XCTUnwrap(viewModel.displayRemaining(asOf: base))

        XCTAssertEqual(remaining, 25 * 60, accuracy: 0.001)
    }

    func testRemainingIsNilWithNoCurrentTask() async {
        let (viewModel, _) = await makeViewModel()

        XCTAssertNil(viewModel.displayRemaining(asOf: base))
        XCTAssertNil(viewModel.remainingFraction(asOf: base))
    }

    // MARK: - Done (4.5)

    func testDoneMarksTaskDoneAndAdvancesToNext() async {
        let clock = TestClock(base)
        let (viewModel, _) = await makeViewModel(
            tasks: [makeTask("first", priority: .high), makeTask("second", priority: .low, minutes: 15)],
            clock: clock
        )
        XCTAssertEqual(viewModel.currentTask?.id, "first")

        clock.now = base.addingTimeInterval(600)
        let succeeded = await viewModel.markDone()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(stored("first", in: viewModel)?.status, .done)
        XCTAssertEqual(viewModel.currentTask?.id, "second")
        XCTAssertEqual(stored("second", in: viewModel)?.status, .current)
        XCTAssertEqual(stored("second", in: viewModel)?.startAt, base.addingTimeInterval(600),
                       "The next task's clock starts when it becomes current")
    }

    func testDoneOnLastTaskLeavesNothingCurrent() async {
        let (viewModel, _) = await makeViewModel(tasks: [makeTask("only")])

        await viewModel.markDone()

        XCTAssertNil(viewModel.currentTask)
        XCTAssertEqual(viewModel.upNextCount, 0)
        XCTAssertEqual(stored("only", in: viewModel)?.status, .done)
    }

    func testDoneFailureKeepsCurrentTaskAndSurfacesError() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        let (viewModel, repo) = await makeViewModel(tasks: [makeTask("a")])
        repo.nextError = WriteError()

        let succeeded = await viewModel.markDone()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, "write failed")
        XCTAssertEqual(viewModel.currentTask?.id, "a")
        XCTAssertEqual(stored("a", in: viewModel)?.status, .current)
        XCTAssertFalse(viewModel.isWorking)
    }

    func testDoneWithNoTaskDoesNothing() async {
        let (viewModel, _) = await makeViewModel()

        let succeeded = await viewModel.markDone()

        XCTAssertFalse(succeeded)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Skip (4.6)

    func testSkipMarksTaskSkippedAndAdvancesToNext() async {
        let (viewModel, _) = await makeViewModel(tasks: [
            makeTask("first", priority: .high),
            makeTask("second", priority: .low)
        ])

        let succeeded = await viewModel.skip()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(stored("first", in: viewModel)?.status, .skipped)
        XCTAssertEqual(viewModel.currentTask?.id, "second")
        XCTAssertEqual(stored("second", in: viewModel)?.status, .current)
    }

    func testSkipFailureSurfacesError() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "skip failed" } }
        let (viewModel, repo) = await makeViewModel(tasks: [makeTask("a")])
        repo.nextError = WriteError()

        let succeeded = await viewModel.skip()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.errorMessage, "skip failed")
        XCTAssertEqual(viewModel.currentTask?.id, "a")
    }

    func testNextActionClearsPreviousError() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        let (viewModel, repo) = await makeViewModel(tasks: [makeTask("a")])
        repo.nextError = WriteError()
        await viewModel.markDone()
        XCTAssertNotNil(viewModel.errorMessage)

        await viewModel.markDone()

        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Errors

    func testObservationFailureSurfacesErrorAndStopsLoading() async {
        struct StreamError: LocalizedError { var errorDescription: String? { "stream broke" } }
        let repo = MockTaskRepository()
        repo.observeError = StreamError()

        let (viewModel, _) = await makeViewModel(repository: repo)

        XCTAssertEqual(viewModel.errorMessage, "stream broke")
        XCTAssertFalse(viewModel.isLoading)
    }
}
