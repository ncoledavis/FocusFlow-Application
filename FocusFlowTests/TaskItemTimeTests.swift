import XCTest
@testable import FocusFlow

final class TaskItemTimeTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testTargetFinishDerivedFromDuration() {
        let task = TaskItem(
            id: "t",
            ownerUid: "u",
            title: "Task",
            scheduleType: .duration,
            durationMinutes: 30,
            startAt: base,
            createdBy: "u"
        )
        XCTAssertEqual(task.targetFinishAt, base.addingTimeInterval(30 * 60))
    }

    func testStoredFinishTakesPrecedence() {
        let stored = base.addingTimeInterval(90 * 60)
        let task = TaskItem(
            id: "t",
            ownerUid: "u",
            title: "Task",
            scheduleType: .duration,
            durationMinutes: 30,
            startAt: base,
            storedTargetFinishAt: stored,
            createdBy: "u"
        )
        // Extended ("add more time") finish wins over the derived value.
        XCTAssertEqual(task.targetFinishAt, stored)
    }

    func testFixedScheduleUsesStoredFinish() {
        let finish = base.addingTimeInterval(45 * 60)
        let task = TaskItem(
            id: "t",
            ownerUid: "u",
            title: "Meeting",
            scheduleType: .fixed,
            startAt: base,
            storedTargetFinishAt: finish,
            createdBy: "u"
        )
        XCTAssertEqual(task.targetFinishAt, finish)
    }

    func testDurationTaskWithoutStartHasNoFinish() {
        let task = TaskItem(
            id: "t",
            ownerUid: "u",
            title: "Task",
            scheduleType: .duration,
            durationMinutes: 30,
            startAt: nil,
            createdBy: "u"
        )
        XCTAssertNil(task.targetFinishAt)
        XCTAssertNil(task.timeRemaining(asOf: base))
    }

    func testTimeRemainingPositiveAndNegative() throws {
        let task = TaskItem(
            id: "t",
            ownerUid: "u",
            title: "Task",
            scheduleType: .duration,
            durationMinutes: 10,
            startAt: base,
            status: .current,
            createdBy: "u"
        )
        // 4 minutes in: 6 minutes (360s) left.
        let fourMinutesIn = base.addingTimeInterval(4 * 60)
        let remainingEarly = try XCTUnwrap(task.timeRemaining(asOf: fourMinutesIn))
        XCTAssertEqual(remainingEarly, 6 * 60, accuracy: 0.001)

        // 12 minutes in: 2 minutes overdue (-120s).
        let twelveMinutesIn = base.addingTimeInterval(12 * 60)
        let remainingLate = try XCTUnwrap(task.timeRemaining(asOf: twelveMinutesIn))
        XCTAssertEqual(remainingLate, -2 * 60, accuracy: 0.001)
    }

    func testIsOverdueOnlyWhenActiveAndElapsed() {
        var task = TaskItem(
            id: "t",
            ownerUid: "u",
            title: "Task",
            scheduleType: .duration,
            durationMinutes: 10,
            startAt: base,
            status: .current,
            createdBy: "u"
        )
        let before = base.addingTimeInterval(5 * 60)
        let after = base.addingTimeInterval(15 * 60)

        XCTAssertFalse(task.isOverdue(asOf: before))
        XCTAssertTrue(task.isOverdue(asOf: after))

        // A completed task is never overdue, even past its finish.
        task.status = .done
        XCTAssertFalse(task.isOverdue(asOf: after))
    }

    func testPriorityComparable() {
        XCTAssertTrue(Priority.low < Priority.medium)
        XCTAssertTrue(Priority.high < Priority.urgent)
        XCTAssertEqual([Priority.urgent, .low, .high, .medium].sorted(),
                       [.low, .medium, .high, .urgent])
    }

    func testLinkPermissionCapabilities() {
        XCTAssertTrue(LinkPermission.view.canView)
        XCTAssertFalse(LinkPermission.view.canAdd)
        XCTAssertFalse(LinkPermission.view.canEdit)

        XCTAssertTrue(LinkPermission.add.canAdd)
        XCTAssertFalse(LinkPermission.add.canEdit)

        XCTAssertTrue(LinkPermission.edit.canEdit)
        XCTAssertTrue(LinkPermission.edit.canAdd)
        XCTAssertTrue(LinkPermission.view < LinkPermission.edit)
    }
}
