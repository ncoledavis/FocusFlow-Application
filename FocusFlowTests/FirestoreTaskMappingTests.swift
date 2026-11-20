import XCTest
@testable import FocusFlow

/// Verifies how `TaskItem` maps to and from Firestore document data. These run
/// without a network connection or a Firebase project.
final class FirestoreTaskMappingTests: XCTestCase {

    private func makeTask(
        notes: String? = "Section 2",
        startAt: Date? = Date(timeIntervalSince1970: 2_000_000),
        finishAt: Date? = Date(timeIntervalSince1970: 2_001_500)
    ) -> TaskItem {
        TaskItem(
            id: "task-1",
            ownerUid: "owner-1",
            title: "Write report",
            notes: notes,
            priority: .high,
            scheduleType: .fixed,
            durationMinutes: nil,
            startAt: startAt,
            storedTargetFinishAt: finishAt,
            status: .current,
            createdBy: "supporter-1",
            order: 3,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    func testRoundTripPreservesEveryField() throws {
        let task = makeTask()

        let data = try FirestoreTaskRepository.encode(task)
        let decoded = try FirestoreTaskRepository.decode(data, id: task.id)

        XCTAssertEqual(decoded, task)
    }

    func testRoundTripPreservesSubSecondPrecision() throws {
        // ISO 8601 strings dropped this in Task 1; Firestore Timestamps keep it.
        let preciseDate = Date(timeIntervalSince1970: 1_000_000.5)
        var task = makeTask()
        task.createdAt = preciseDate

        let data = try FirestoreTaskRepository.encode(task)
        let decoded = try FirestoreTaskRepository.decode(data, id: task.id)

        XCTAssertEqual(decoded.createdAt, preciseDate)
    }

    func testStoredFinishIsPersistedAsTargetFinishAt() throws {
        let data = try FirestoreTaskRepository.encode(makeTask())

        XCTAssertNotNil(data["targetFinishAt"])
        XCTAssertNil(data["storedTargetFinishAt"])
    }

    func testEnumsAreStoredAsRawStrings() throws {
        let data = try FirestoreTaskRepository.encode(makeTask())

        XCTAssertEqual(data["priority"] as? String, "high")
        XCTAssertEqual(data["scheduleType"] as? String, "fixed")
        XCTAssertEqual(data["status"] as? String, "current")
    }

    func testNilOptionalsAreOmitted() throws {
        let task = makeTask(notes: nil, startAt: nil, finishAt: nil)

        let data = try FirestoreTaskRepository.encode(task)

        XCTAssertNil(data["notes"])
        XCTAssertNil(data["startAt"])
        XCTAssertNil(data["targetFinishAt"])
        XCTAssertNil(data["durationMinutes"])
    }

    func testDocumentIDIsAuthoritativeForID() throws {
        var data = try FirestoreTaskRepository.encode(makeTask())
        data["id"] = "stale-id"

        let decoded = try FirestoreTaskRepository.decode(data, id: "real-doc-id")

        XCTAssertEqual(decoded.id, "real-doc-id")
    }

    func testDecodeFillsIDWhenFieldIsMissing() throws {
        var data = try FirestoreTaskRepository.encode(makeTask())
        data["id"] = nil

        let decoded = try FirestoreTaskRepository.decode(data, id: "from-doc")

        XCTAssertEqual(decoded.id, "from-doc")
    }

    func testDecodeThrowsForMalformedDocument() throws {
        var data = try FirestoreTaskRepository.encode(makeTask())
        data["title"] = nil

        XCTAssertThrowsError(try FirestoreTaskRepository.decode(data, id: "task-1"))
    }

    func testComputedFinishIsNeverPersisted() throws {
        // A duration task derives its finish from startAt + duration; only an
        // explicit stored finish should reach Firestore.
        let task = TaskItem(
            id: "d",
            ownerUid: "o",
            title: "Derived",
            scheduleType: .duration,
            durationMinutes: 30,
            startAt: Date(timeIntervalSince1970: 1_000),
            createdBy: "o"
        )
        XCTAssertNotNil(task.targetFinishAt)

        let data = try FirestoreTaskRepository.encode(task)

        XCTAssertNil(data["targetFinishAt"])
    }
}
