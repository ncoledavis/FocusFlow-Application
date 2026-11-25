import XCTest
import Combine
@testable import FocusFlow

/// Covers Task 5: detecting that time has run out, "add more time", and the
/// "time's up" notification lifecycle.
@MainActor
final class FocusViewModelExpiryTests: XCTestCase {

    private let owner = "owner-1"
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private final class TestClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    /// Everything a test needs to drive the view model by hand.
    private struct Harness {
        let viewModel: FocusViewModel
        let repository: MockTaskRepository
        let notifications: MockNotificationService
        let clock: TestClock
        let ticker: PassthroughSubject<Void, Never>

        /// Moves the clock and fires one tick, like a second passing.
        func advance(to date: Date) {
            clock.now = date
            ticker.send()
        }
    }

    private func makeTask(
        _ id: String,
        priority: Priority = .medium,
        status: TaskStatus = .pending,
        minutes: Int = 10,
        startAt: Date? = nil,
        order: Int = 0
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
            order: order
        )
    }

    private func makeHarness(
        tasks: [TaskItem] = [],
        permission: NotificationPermission = .granted
    ) async -> Harness {
        let repository = MockTaskRepository(initialTasks: tasks)
        let notifications = MockNotificationService(permission: permission)
        let clock = TestClock(base)
        let ticker = PassthroughSubject<Void, Never>()
        let viewModel = FocusViewModel(
            repository: repository,
            ownerUid: owner,
            notificationService: notifications,
            clock: { clock.now },
            ticker: ticker.eraseToAnyPublisher()
        )
        viewModel.start()
        await viewModel.permissionTask?.value
        await viewModel.promotionTask?.value
        return Harness(viewModel: viewModel, repository: repository, notifications: notifications,
                       clock: clock, ticker: ticker)
    }

    private func stored(_ id: String, in harness: Harness) -> TaskItem? {
        harness.viewModel.allTasks.first { $0.id == id }
    }

    // MARK: - Overdue detection (5.3)

    func testNotOverdueWhileTimeRemains() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])

        harness.advance(to: base.addingTimeInterval(5 * 60))

        XCTAssertFalse(harness.viewModel.isOverdue)
    }

    func testBecomesOverdueWhenTheCountdownReachesZero() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])

        harness.advance(to: base.addingTimeInterval(10 * 60 - 1))
        XCTAssertFalse(harness.viewModel.isOverdue, "One second left is not overdue")

        harness.advance(to: base.addingTimeInterval(10 * 60))
        XCTAssertTrue(harness.viewModel.isOverdue, "Exactly zero remaining is overdue")
    }

    func testStaysOverdueAsTimePasses() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])

        harness.advance(to: base.addingTimeInterval(11 * 60))
        harness.advance(to: base.addingTimeInterval(12 * 60))

        XCTAssertTrue(harness.viewModel.isOverdue)
    }

    func testNotOverdueWithNoCurrentTask() async {
        let harness = await makeHarness()

        harness.advance(to: base.addingTimeInterval(3_600))

        XCTAssertFalse(harness.viewModel.isOverdue)
    }

    func testTaskAlreadyPastItsFinishIsOverdueAsSoonAsItLoads() async {
        // e.g. the app was closed while the task's time ran out.
        let harness = await makeHarness(tasks: [
            makeTask("late", status: .current, minutes: 10, startAt: base.addingTimeInterval(-20 * 60))
        ])

        XCTAssertTrue(harness.viewModel.isOverdue, "No tick is needed to detect it")
    }

    func testDoneClearsTheOverdueState() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        harness.advance(to: base.addingTimeInterval(11 * 60))
        XCTAssertTrue(harness.viewModel.isOverdue)

        await harness.viewModel.markDone()

        XCTAssertFalse(harness.viewModel.isOverdue)
    }

    func testSkipAdvancesToANewTaskThatIsNotOverdue() async {
        let harness = await makeHarness(tasks: [
            makeTask("first", priority: .high, minutes: 10),
            makeTask("second", priority: .low, minutes: 10)
        ])
        harness.advance(to: base.addingTimeInterval(11 * 60))
        XCTAssertTrue(harness.viewModel.isOverdue)

        await harness.viewModel.skip()

        XCTAssertEqual(harness.viewModel.currentTask?.id, "second")
        XCTAssertFalse(harness.viewModel.isOverdue, "The next task's clock starts when it becomes current")
    }

    // MARK: - Add more time (5.5)

    func testAddMoreTimeCountsFromNowWhenAlreadyOverdue() async throws {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        let twoMinutesLate = base.addingTimeInterval(12 * 60)
        harness.advance(to: twoMinutesLate)

        let succeeded = await harness.viewModel.addMoreTime(minutes: 10)

        XCTAssertTrue(succeeded)
        let task = try XCTUnwrap(stored("a", in: harness))
        XCTAssertEqual(task.targetFinishAt, twoMinutesLate.addingTimeInterval(10 * 60),
                       "10 minutes from now, not 8")
        let remaining = try XCTUnwrap(harness.viewModel.displayRemaining(asOf: twoMinutesLate))
        XCTAssertEqual(remaining, 10 * 60, accuracy: 0.001, "The countdown resets")
        XCTAssertFalse(harness.viewModel.isOverdue)
    }

    func testAddMoreTimeBeforeExpiryExtendsTheExistingFinish() async throws {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        harness.advance(to: base.addingTimeInterval(4 * 60))

        await harness.viewModel.addMoreTime(minutes: 5)

        let task = try XCTUnwrap(stored("a", in: harness))
        XCTAssertEqual(task.targetFinishAt, base.addingTimeInterval(15 * 60))
    }

    func testAddMoreTimeKeepsTheTaskRunningWithItsOriginalStart() async throws {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        harness.advance(to: base.addingTimeInterval(12 * 60))

        await harness.viewModel.addMoreTime(minutes: 10)

        let task = try XCTUnwrap(stored("a", in: harness))
        XCTAssertEqual(task.status, .current)
        XCTAssertEqual(task.startAt, base)
        XCTAssertEqual(task.durationMinutes, 10)
    }

    func testTaskCanExpireAgainAfterBeingExtended() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        harness.advance(to: base.addingTimeInterval(11 * 60))
        await harness.viewModel.addMoreTime(minutes: 5)
        XCTAssertFalse(harness.viewModel.isOverdue)

        harness.advance(to: base.addingTimeInterval(16 * 60 - 1))
        XCTAssertFalse(harness.viewModel.isOverdue)

        harness.advance(to: base.addingTimeInterval(16 * 60))
        XCTAssertTrue(harness.viewModel.isOverdue)
    }

    func testAddMoreTimeRejectsNonPositiveMinutes() async throws {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        let before = try XCTUnwrap(stored("a", in: harness))

        let zero = await harness.viewModel.addMoreTime(minutes: 0)
        let negative = await harness.viewModel.addMoreTime(minutes: -5)

        XCTAssertFalse(zero)
        XCTAssertFalse(negative)
        XCTAssertEqual(stored("a", in: harness), before)
    }

    func testAddMoreTimeFailureKeepsOverdueAndSurfacesError() async {
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        harness.advance(to: base.addingTimeInterval(11 * 60))
        harness.repository.nextError = WriteError()

        let succeeded = await harness.viewModel.addMoreTime(minutes: 10)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(harness.viewModel.errorMessage, "write failed")
        XCTAssertTrue(harness.viewModel.isOverdue)
        XCTAssertFalse(harness.viewModel.isWorking)
    }

    func testAddMoreTimeWithNoCurrentTaskDoesNothing() async {
        let harness = await makeHarness()

        let succeeded = await harness.viewModel.addMoreTime(minutes: 10)

        XCTAssertFalse(succeeded)
        XCTAssertNil(harness.viewModel.errorMessage)
    }

    func testExtensionOptionsAreOfferedInMinutes() {
        XCTAssertEqual(FocusViewModel.extensionOptions, [5, 10, 15, 30])
    }

    // MARK: - Notification permission (5.1)

    func testAsksForNotificationPermissionOnStart() async {
        let harness = await makeHarness(permission: .granted)

        XCTAssertEqual(harness.notifications.permissionRequestCount, 1)
        XCTAssertEqual(harness.viewModel.notificationPermission, .granted)
    }

    func testDeniedPermissionIsExposedForTheFallbackNote() async {
        let harness = await makeHarness(permission: .denied)

        XCTAssertEqual(harness.viewModel.notificationPermission, .denied)
    }

    func testRefreshingPermissionPicksUpAChangeMadeInSettings() async {
        let harness = await makeHarness(permission: .denied)

        harness.notifications.permission = .granted
        harness.viewModel.refreshNotificationPermission()
        await harness.viewModel.permissionTask?.value

        XCTAssertEqual(harness.viewModel.notificationPermission, .granted)
    }

    func testOverduePromptStillWorksWhenNotificationsAreDenied() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)], permission: .denied)

        harness.advance(to: base.addingTimeInterval(11 * 60))

        XCTAssertTrue(harness.viewModel.isOverdue)
    }

    // MARK: - Notification scheduling (5.2)

    func testSchedulesANotificationAtTheFinishTimeWhenTheTaskStarts() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 25)])

        XCTAssertEqual(harness.notifications.scheduled, [
            .init(taskId: "a", title: "Task a", date: base.addingTimeInterval(25 * 60))
        ])
    }

    func testDoesNotRescheduleOnUnrelatedListChanges() async throws {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 25)])

        try await harness.repository.create(makeTask("b", priority: .low))
        await harness.viewModel.promotionTask?.value

        XCTAssertEqual(harness.notifications.scheduled.count, 1)
        XCTAssertTrue(harness.notifications.cancelledTaskIds.isEmpty)
    }

    func testAddMoreTimeReschedulesTheNotificationForTheNewFinish() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 10)])
        harness.advance(to: base.addingTimeInterval(11 * 60))

        await harness.viewModel.addMoreTime(minutes: 10)

        XCTAssertEqual(harness.notifications.scheduled.count, 2)
        XCTAssertEqual(harness.notifications.scheduled.last?.taskId, "a")
        XCTAssertEqual(harness.notifications.scheduled.last?.date, base.addingTimeInterval(21 * 60))
    }

    func testDoneCancelsTheNotification() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 25)])

        await harness.viewModel.markDone()

        XCTAssertEqual(harness.notifications.cancelledTaskIds, ["a"])
    }

    func testSkipCancelsTheNotification() async {
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 25)])

        await harness.viewModel.skip()

        XCTAssertEqual(harness.notifications.cancelledTaskIds, ["a"])
    }

    func testAdvancingSchedulesTheNextTasksNotification() async {
        let harness = await makeHarness(tasks: [
            makeTask("first", priority: .high, minutes: 25),
            makeTask("second", priority: .low, minutes: 15)
        ])
        let later = base.addingTimeInterval(5 * 60)
        harness.clock.now = later

        await harness.viewModel.markDone()

        XCTAssertEqual(harness.notifications.cancelledTaskIds, ["first"])
        XCTAssertEqual(harness.notifications.scheduled.last?.taskId, "second")
        XCTAssertEqual(harness.notifications.scheduled.last?.date, later.addingTimeInterval(15 * 60))
    }

    func testNoNotificationIsScheduledForAFinishInThePast() async {
        let harness = await makeHarness(tasks: [
            makeTask("late", status: .current, minutes: 10, startAt: base.addingTimeInterval(-20 * 60))
        ])

        XCTAssertTrue(harness.notifications.scheduled.isEmpty)
    }

    func testNoNotificationWithNoTasks() async {
        let harness = await makeHarness()

        XCTAssertTrue(harness.notifications.scheduled.isEmpty)
        XCTAssertTrue(harness.notifications.cancelledTaskIds.isEmpty)
    }

    func testFailedDoneKeepsTheNotification() async {
        struct WriteError: Error {}
        let harness = await makeHarness(tasks: [makeTask("a", minutes: 25)])
        harness.repository.nextError = WriteError()

        await harness.viewModel.markDone()

        XCTAssertTrue(harness.notifications.cancelledTaskIds.isEmpty)
    }
}
