import XCTest
@testable import FocusFlow

/// Permission gating (6.8): what each kind of person can do in a task list.
@MainActor
final class TaskListAccessTests: XCTestCase {

    private let owner = "owner"
    private let helper = "helper"

    private func makeTask(
        _ id: String,
        priority: Priority = .medium,
        status: TaskStatus = .pending,
        order: Int = 0,
        createdAt: TimeInterval = 1_000,
        startAt: Date? = nil
    ) -> TaskItem {
        TaskItem(
            id: id,
            ownerUid: owner,
            title: "Task \(id)",
            priority: priority,
            durationMinutes: 25,
            startAt: startAt,
            status: status,
            createdBy: owner,
            order: order,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }

    private func makeViewModel(
        access: TaskListAccess,
        tasks: [TaskItem] = []
    ) -> (TaskListViewModel, MockTaskRepository) {
        let repository = MockTaskRepository(initialTasks: tasks)
        let viewModel = TaskListViewModel(
            repository: repository,
            ownerUid: owner,
            currentUid: access == .owner ? owner : helper,
            access: access
        )
        viewModel.start()
        return (viewModel, repository)
    }

    private func assertDenied(
        _ succeeded: Bool,
        _ viewModel: TaskListViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(succeeded, file: file, line: line)
        XCTAssertTrue(
            viewModel.errorMessage?.contains("permission") == true,
            "Expected a permission message, got \(String(describing: viewModel.errorMessage))",
            file: file,
            line: line
        )
    }

    // MARK: - The capability table

    func testCapabilitiesForEachRole() {
        XCTAssertTrue(TaskListAccess.owner.canAdd)
        XCTAssertTrue(TaskListAccess.owner.canReorder)
        XCTAssertTrue(TaskListAccess.owner.canModify)

        XCTAssertFalse(TaskListAccess.supporter(.view).canAdd)
        XCTAssertFalse(TaskListAccess.supporter(.view).canReorder)
        XCTAssertFalse(TaskListAccess.supporter(.view).canModify)

        XCTAssertTrue(TaskListAccess.supporter(.add).canAdd)
        XCTAssertFalse(TaskListAccess.supporter(.add).canReorder)
        XCTAssertFalse(TaskListAccess.supporter(.add).canModify)

        XCTAssertTrue(TaskListAccess.supporter(.edit).canAdd)
        XCTAssertTrue(TaskListAccess.supporter(.edit).canReorder)
        XCTAssertFalse(TaskListAccess.supporter(.edit).canModify, "Only the owner edits or deletes")
    }

    func testOnlySupportersAreMarkedAsSupporters() {
        XCTAssertFalse(TaskListAccess.owner.isSupporter)
        XCTAssertTrue(TaskListAccess.supporter(.view).isSupporter)
    }

    func testEachRoleHasADescription() {
        let descriptions = [
            TaskListAccess.owner,
            .supporter(.view),
            .supporter(.add),
            .supporter(.edit)
        ].map(\.roleDescription)
        XCTAssertEqual(Set(descriptions).count, 4)
    }

    // MARK: - View only

    func testViewOnlySupporterSeesTheTasks() {
        let (viewModel, _) = makeViewModel(access: .supporter(.view), tasks: [makeTask("a"), makeTask("b")])

        XCTAssertEqual(viewModel.allTasks.count, 2)
    }

    func testViewOnlySupporterCannotAddReorderEditOrDelete() async {
        let task = makeTask("a", priority: .low)
        let (viewModel, _) = makeViewModel(access: .supporter(.view), tasks: [task])

        assertDenied(await viewModel.addTask(title: "New", schedule: .duration(minutes: 10)), viewModel)
        assertDenied(await viewModel.setPriority(.urgent, for: task), viewModel)
        assertDenied(await viewModel.move(task, .down), viewModel)
        assertDenied(await viewModel.update(task), viewModel)
        assertDenied(await viewModel.delete(task), viewModel)

        XCTAssertEqual(viewModel.allTasks, [task], "Nothing changed")
    }

    // MARK: - Add

    func testAddSupporterCanAddATaskAuthoredByThem() async throws {
        let (viewModel, _) = makeViewModel(access: .supporter(.add))

        let succeeded = await viewModel.addTask(title: "Call the pharmacy", priority: .high, schedule: .duration(minutes: 15))

        XCTAssertTrue(succeeded)
        let task = try XCTUnwrap(viewModel.allTasks.first)
        XCTAssertEqual(task.ownerUid, owner, "The task goes in the owner's list")
        XCTAssertEqual(task.createdBy, helper, "and is marked as the supporter's")
        XCTAssertEqual(task.status, .pending)
        XCTAssertEqual(task.priority, .high)
    }

    func testAddSupporterCannotReorderEditOrDelete() async {
        let task = makeTask("a")
        let (viewModel, _) = makeViewModel(access: .supporter(.add), tasks: [task])

        assertDenied(await viewModel.setPriority(.urgent, for: task), viewModel)
        assertDenied(await viewModel.move(task, .up), viewModel)
        assertDenied(await viewModel.update(task), viewModel)
        assertDenied(await viewModel.delete(task), viewModel)
        XCTAssertEqual(viewModel.allTasks, [task])
    }

    // MARK: - Edit

    func testEditSupporterCanAddATask() async {
        let (viewModel, _) = makeViewModel(access: .supporter(.edit))

        let succeeded = await viewModel.addTask(title: "New", schedule: .duration(minutes: 10))

        XCTAssertTrue(succeeded)
        XCTAssertEqual(viewModel.allTasks.first?.createdBy, helper)
    }

    func testEditSupporterChangesOnlyPriority() async throws {
        let started = Date(timeIntervalSince1970: 5_000)
        let task = makeTask("a", priority: .low, status: .current, order: 4, startAt: started)
        let (viewModel, _) = makeViewModel(access: .supporter(.edit), tasks: [task])

        let succeeded = await viewModel.setPriority(.urgent, for: task)

        XCTAssertTrue(succeeded)
        let changed = try XCTUnwrap(viewModel.allTasks.first)
        XCTAssertEqual(changed.priority, .urgent)
        var expected = task
        expected.priority = .urgent
        XCTAssertEqual(changed, expected, "Status, start time, order and everything else are untouched")
    }

    func testEditSupporterCannotEditOrDeleteTasks() async {
        let task = makeTask("a")
        let (viewModel, _) = makeViewModel(access: .supporter(.edit), tasks: [task])
        var renamed = task
        renamed.title = "Renamed"

        assertDenied(await viewModel.update(renamed), viewModel)
        assertDenied(await viewModel.delete(task), viewModel)
        XCTAssertEqual(viewModel.allTasks.first?.title, "Task a")
    }

    func testEditSupporterCanMoveTasks() async {
        let tasks = [makeTask("a", order: 0), makeTask("b", order: 1)]
        let (viewModel, _) = makeViewModel(access: .supporter(.edit), tasks: tasks)

        let moved = await viewModel.move(tasks[1], .up)

        XCTAssertTrue(moved)
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["b", "a"])
    }

    // MARK: - Owner

    func testOwnerCanDoEverything() async {
        let task = makeTask("a")
        let (viewModel, _) = makeViewModel(access: .owner, tasks: [task])

        let added = await viewModel.addTask(title: "New", schedule: .duration(minutes: 10))
        let prioritized = await viewModel.setPriority(.high, for: task)
        var renamed = task
        renamed.title = "Renamed"
        let updated = await viewModel.update(renamed)
        let deleted = await viewModel.delete(task)

        XCTAssertTrue(added)
        XCTAssertTrue(prioritized)
        XCTAssertTrue(updated)
        XCTAssertTrue(deleted)
        XCTAssertEqual(viewModel.allTasks.count, 1)
    }

    // MARK: - Permission changes while the list is open

    func testDowngradingAnOpenListStopsEditsImmediately() async {
        let task = makeTask("a")
        let (viewModel, _) = makeViewModel(access: .supporter(.edit), tasks: [task])
        let beforeDowngrade = await viewModel.setPriority(.high, for: task)
        XCTAssertTrue(beforeDowngrade)

        viewModel.access = .supporter(.view)

        assertDenied(await viewModel.setPriority(.urgent, for: viewModel.allTasks[0]), viewModel)
        XCTAssertEqual(viewModel.allTasks.first?.priority, .high)
    }

    func testUpgradingAnOpenListAllowsAddingImmediately() async {
        let (viewModel, _) = makeViewModel(access: .supporter(.view))
        assertDenied(await viewModel.addTask(title: "New", schedule: .duration(minutes: 10)), viewModel)

        viewModel.access = .supporter(.add)
        let succeeded = await viewModel.addTask(title: "New", schedule: .duration(minutes: 10))

        XCTAssertTrue(succeeded)
        XCTAssertNil(viewModel.errorMessage, "A successful action clears the old denial")
    }

    // MARK: - Reordering (move up / down)

    func testMovingUpSwapsWithThePreviousTask() async {
        let tasks = [makeTask("a", order: 0), makeTask("b", order: 1), makeTask("c", order: 2)]
        let (viewModel, _) = makeViewModel(access: .owner, tasks: tasks)

        let moved = await viewModel.move(tasks[2], .up)

        XCTAssertTrue(moved)
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["a", "c", "b"])
    }

    func testMovingDownSwapsWithTheNextTask() async {
        let tasks = [makeTask("a", order: 0), makeTask("b", order: 1), makeTask("c", order: 2)]
        let (viewModel, _) = makeViewModel(access: .owner, tasks: tasks)

        let moved = await viewModel.move(tasks[0], .down)

        XCTAssertTrue(moved)
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["b", "a", "c"])
    }

    func testMovingPastTheEndsDoesNothing() async {
        let tasks = [makeTask("a", order: 0), makeTask("b", order: 1)]
        let (viewModel, _) = makeViewModel(access: .owner, tasks: tasks)

        let up = await viewModel.move(tasks[0], .up)
        let down = await viewModel.move(tasks[1], .down)

        XCTAssertFalse(up)
        XCTAssertFalse(down)
        XCTAssertNil(viewModel.errorMessage, "Being at the end isn't an error")
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["a", "b"])
    }

    func testMovingStaysWithinOnePriority() async {
        let tasks = [
            makeTask("high", priority: .high, order: 0),
            makeTask("m1", priority: .medium, order: 0),
            makeTask("m2", priority: .medium, order: 1),
            makeTask("low", priority: .low, order: 0)
        ]
        let (viewModel, _) = makeViewModel(access: .owner, tasks: tasks)

        let movedOutOfGroup = await viewModel.move(tasks[2], .down)
        let moved = await viewModel.move(tasks[1], .down)

        XCTAssertFalse(movedOutOfGroup, "m2 is last in its priority; it doesn't jump to low")
        XCTAssertTrue(moved)
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["high", "m2", "m1", "low"])
    }

    func testMovingResolvesTiesInOrder() async throws {
        let tasks = [
            makeTask("a", order: 0, createdAt: 1),
            makeTask("b", order: 0, createdAt: 2),
            makeTask("c", order: 0, createdAt: 3)
        ]
        let (viewModel, _) = makeViewModel(access: .owner, tasks: tasks)
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["a", "b", "c"])

        await viewModel.move(tasks[2], .up)

        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(viewModel.activeTasks.map(\.order), [0, 1, 2], "Ties are replaced with distinct positions")
    }

    func testFinishedTasksAreNotPartOfTheOrdering() async {
        let tasks = [
            makeTask("a", order: 0),
            makeTask("done", status: .done, order: 1),
            makeTask("b", order: 2)
        ]
        let (viewModel, _) = makeViewModel(access: .owner, tasks: tasks)

        let movedDone = await viewModel.move(tasks[1], .up)
        let movedB = await viewModel.move(tasks[2], .up)

        XCTAssertFalse(movedDone)
        XCTAssertTrue(movedB)
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["b", "a"])
    }

    func testMoveFailureSurfacesTheError() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        let tasks = [makeTask("a", order: 0), makeTask("b", order: 1)]
        let (viewModel, repository) = makeViewModel(access: .owner, tasks: tasks)
        repository.nextError = WriteError()

        let moved = await viewModel.move(tasks[1], .up)

        XCTAssertFalse(moved)
        XCTAssertEqual(viewModel.errorMessage, "write failed")
        XCTAssertEqual(viewModel.activeTasks.map(\.id), ["a", "b"])
    }
}
