import Foundation
import Combine
import FirebaseFirestore

/// `TaskRepository` backed by Cloud Firestore.
///
/// ## Schema: `tasks/{taskId}`
/// The document ID equals `TaskItem.id` (a client-generated UUID).
///
/// | Field                | Type      | Notes                                                    |
/// | -------------------- | --------- | -------------------------------------------------------- |
/// | `id`                 | string    | Mirrors the document ID.                                 |
/// | `ownerUid`           | string    | UID of the ADHD user who owns the task list.             |
/// | `title`              | string    | Required.                                                |
/// | `notes`              | string?   | Optional free text.                                      |
/// | `priority`           | string    | `low` / `medium` / `high` / `urgent`.                    |
/// | `scheduleType`       | string    | `duration` or `fixed`.                                   |
/// | `durationMinutes`    | number?   | Allotted minutes for `duration` tasks.                   |
/// | `startAt`            | timestamp?| Slot start (fixed) or when the task became current.      |
/// | `targetFinishAt`     | timestamp?| Fixed slot end, or an extended finish ("add more time"). |
/// | `status`             | string    | `pending` / `current` / `done` / `skipped`.              |
/// | `createdBy`          | string    | UID of the creator (owner or a supporter).               |
/// | `order`              | number    | Manual ordering within the same priority.                |
/// | `createdAt`          | timestamp | Creation time.                                           |
///
/// Optional fields that are `nil` are omitted from the document. Dates are
/// stored as Firestore `Timestamp`s, which keep sub-second precision.
///
/// The owner query (`ownerUid == uid`) needs no composite index because all
/// sorting happens client-side in `TaskListViewModel`.
final class FirestoreTaskRepository: TaskRepository {

    static let collectionName = "tasks"

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var collection: CollectionReference {
        db.collection(Self.collectionName)
    }

    // MARK: - Writes

    func create(_ task: TaskItem) async throws {
        try await collection.document(task.id).setData(Self.encode(task))
    }

    func update(_ task: TaskItem) async throws {
        // Full overwrite so cleared optional fields are removed, not left stale.
        try await collection.document(task.id).setData(Self.encode(task))
    }

    func delete(taskId: String) async throws {
        try await collection.document(taskId).delete()
    }

    // MARK: - Real-time observation

    func observeTasks(forOwner ownerUid: String) -> AnyPublisher<[TaskItem], Error> {
        let query = collection.whereField("ownerUid", isEqualTo: ownerUid)

        // Deferred so each subscriber gets its own listener, removed on
        // cancellation or completion.
        return Deferred { () -> AnyPublisher<[TaskItem], Error> in
            let subject = PassthroughSubject<[TaskItem], Error>()
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    subject.send(completion: .failure(error))
                    return
                }
                guard let snapshot else { return }
                subject.send(Self.decodeTasks(from: snapshot.documents))
            }
            return subject
                .handleEvents(
                    receiveCompletion: { _ in registration.remove() },
                    receiveCancel: { registration.remove() }
                )
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Mapping

    /// Encodes a task into Firestore document data.
    static func encode(_ task: TaskItem) throws -> [String: Any] {
        try Firestore.Encoder().encode(task)
    }

    /// Decodes Firestore document data into a task. The document ID is
    /// authoritative for `id`.
    static func decode(_ data: [String: Any], id: String) throws -> TaskItem {
        var data = data
        data["id"] = id
        return try Firestore.Decoder().decode(TaskItem.self, from: data)
    }

    /// Decodes a snapshot's documents, skipping any that are malformed rather
    /// than failing the whole stream.
    private static func decodeTasks(from documents: [QueryDocumentSnapshot]) -> [TaskItem] {
        documents.compactMap { document in
            do {
                return try decode(document.data(), id: document.documentID)
            } catch {
                #if DEBUG
                print("[FirestoreTaskRepository] Skipping malformed task \(document.documentID): \(error)")
                #endif
                return nil
            }
        }
    }
}
