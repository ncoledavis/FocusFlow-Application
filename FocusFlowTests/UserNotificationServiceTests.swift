import XCTest
import UserNotifications
@testable import FocusFlow

/// Tests the request the real notification service builds. They don't touch
/// the system notification center.
final class UserNotificationServiceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRequestFiresAtTheFinishTime() throws {
        let finish = now.addingTimeInterval(25 * 60)

        let request = try XCTUnwrap(
            UserNotificationService.makeRequest(taskId: "abc", title: "Write report", at: finish, now: now)
        )

        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 25 * 60, accuracy: 0.001)
        XCTAssertFalse(trigger.repeats)
    }

    func testRequestIdentifierIsPerTaskSoReschedulingReplacesIt() throws {
        let finish = now.addingTimeInterval(60)

        let first = try XCTUnwrap(UserNotificationService.makeRequest(taskId: "abc", title: "T", at: finish, now: now))
        let second = try XCTUnwrap(UserNotificationService.makeRequest(taskId: "abc", title: "T", at: finish, now: now))
        let other = try XCTUnwrap(UserNotificationService.makeRequest(taskId: "xyz", title: "T", at: finish, now: now))

        XCTAssertEqual(first.identifier, "task-expiry-abc")
        XCTAssertEqual(first.identifier, second.identifier)
        XCTAssertNotEqual(first.identifier, other.identifier)
        XCTAssertEqual(UserNotificationService.identifier(for: "abc"), first.identifier)
    }

    func testRequestContentNamesTheTask() throws {
        let request = try XCTUnwrap(
            UserNotificationService.makeRequest(
                taskId: "abc", title: "Write report", at: now.addingTimeInterval(60), now: now
            )
        )

        XCTAssertEqual(request.content.title, "Time's up")
        XCTAssertTrue(request.content.body.contains("Write report"))
        XCTAssertNotNil(request.content.sound)
    }

    func testNoRequestWhenTheFinishIsNotInTheFuture() {
        XCTAssertNil(UserNotificationService.makeRequest(taskId: "a", title: "T", at: now, now: now))
        XCTAssertNil(
            UserNotificationService.makeRequest(taskId: "a", title: "T", at: now.addingTimeInterval(-30), now: now)
        )
    }
}
