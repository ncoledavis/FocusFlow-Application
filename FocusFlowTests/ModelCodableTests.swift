import XCTest
@testable import FocusFlow

final class ModelCodableTests: XCTestCase {

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try makeEncoder().encode(value)
        return try makeDecoder().decode(T.self, from: data)
    }

    func testAppUserRoundTrip() throws {
        let user = AppUser(
            id: "uid-1",
            email: "a@b.com",
            displayName: "Alex",
            isSupporter: true,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        XCTAssertEqual(try roundTrip(user), user)
    }

    func testTaskItemDurationRoundTrip() throws {
        let task = TaskItem(
            id: "t-1",
            ownerUid: "uid-1",
            title: "Write report",
            notes: "Section 2",
            priority: .high,
            scheduleType: .duration,
            durationMinutes: 45,
            startAt: Date(timeIntervalSince1970: 2_000_000),
            status: .current,
            createdBy: "uid-1",
            order: 3,
            createdAt: Date(timeIntervalSince1970: 2_100_000)
        )
        XCTAssertEqual(try roundTrip(task), task)
    }

    func testTaskItemFixedRoundTrip() throws {
        let task = TaskItem(
            id: "t-2",
            ownerUid: "uid-1",
            title: "Standup",
            priority: .medium,
            scheduleType: .fixed,
            startAt: Date(timeIntervalSince1970: 3_000_000),
            storedTargetFinishAt: Date(timeIntervalSince1970: 3_000_900),
            status: .pending,
            createdBy: "uid-2",
            order: 0,
            createdAt: Date(timeIntervalSince1970: 3_100_000)
        )
        XCTAssertEqual(try roundTrip(task), task)
    }

    func testSupporterLinkRoundTrip() throws {
        let link = SupporterLink(
            id: "l-1",
            ownerUid: "uid-1",
            supporterUid: "uid-2",
            inviteCode: "ABC123",
            permission: .edit,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 500)
        )
        XCTAssertEqual(try roundTrip(link), link)
    }

    func testCalendarEventRoundTrip() throws {
        let event = CalendarEvent(
            id: "e-1",
            title: "Dentist",
            startAt: Date(timeIntervalSince1970: 4_000_000),
            endAt: Date(timeIntervalSince1970: 4_003_600),
            isAllDay: false,
            calendarName: "Personal"
        )
        XCTAssertEqual(try roundTrip(event), event)
    }

    func testEnumRawValuesRoundTrip() throws {
        XCTAssertEqual(try roundTrip(Priority.urgent), .urgent)
        XCTAssertEqual(try roundTrip(TaskStatus.skipped), .skipped)
        XCTAssertEqual(try roundTrip(ScheduleType.fixed), .fixed)
        XCTAssertEqual(try roundTrip(LinkPermission.add), .add)
        XCTAssertEqual(try roundTrip(LinkStatus.pending), .pending)
    }
}
