import Foundation
import Combine
import FirebaseFirestore

/// `LinkRepository` backed by Cloud Firestore.
///
/// ## Schema
/// Links use two collections, because a pending invite and an active link need
/// different security properties.
///
/// **`invites/{code}`**: a pending invite. The document ID *is* the random
/// invite code, so only someone who has the code can fetch it, and rules don't
/// let anyone list invites they don't own. Accepting deletes it, so a code
/// works once.
///
/// | Field        | Type      | Notes                                   |
/// | ------------ | --------- | --------------------------------------- |
/// | `ownerUid`   | string    | The user who created the invite.        |
/// | `ownerEmail` | string?   | Display only.                           |
/// | `permission` | string    | `view` / `add` / `edit`.                |
/// | `createdAt`  | timestamp |                                         |
///
/// **`links/{ownerUid}_{supporterUid}`**: an active link. The ID is derived
/// from both UIDs so the task security rules can find a supporter's link by
/// path (rules can't run queries).
///
/// | Field           | Type      | Notes                                    |
/// | --------------- | --------- | ---------------------------------------- |
/// | `id`            | string    | Mirrors the document ID.                 |
/// | `ownerUid`      | string    | The task list's owner.                   |
/// | `supporterUid`  | string    | The supporter.                           |
/// | `ownerEmail`    | string?   | Display only.                            |
/// | `supporterEmail`| string?   | Display only.                            |
/// | `inviteCode`    | string    | The invite this link came from.          |
/// | `permission`    | string    | `view` / `add` / `edit`.                 |
/// | `status`        | string    | Always `active` here.                    |
/// | `createdAt`     | timestamp |                                          |
///
/// The security rules (`firestore.rules`) enforce who may create, change, and
/// read each of these. The emails are written by the client and are never used
/// for access decisions.
final class FirestoreLinkRepository: LinkRepository {

    static let invitesCollection = "invites"
    static let linksCollection = "links"

    /// The stored shape of an invite (the code is the document ID).
    struct InviteDocument: Codable, Equatable {
        var ownerUid: String
        var ownerEmail: String?
        var permission: LinkPermission
        var createdAt: Date
    }

    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    private var invites: CollectionReference { db.collection(Self.invitesCollection) }
    private var links: CollectionReference { db.collection(Self.linksCollection) }

    // MARK: - Writes

    func createInvite(ownerUid: String, ownerEmail: String?, permission: LinkPermission) async throws -> SupporterLink {
        let code = InviteCode.generate()
        let invite = InviteDocument(
            ownerUid: ownerUid,
            ownerEmail: ownerEmail,
            permission: permission,
            createdAt: Date()
        )
        try await invites.document(code).setData(Self.encode(invite))
        return Self.pendingLink(code: code, invite: invite)
    }

    func acceptInvite(code: String, supporterUid: String, supporterEmail: String?) async throws -> SupporterLink {
        let inviteRef = invites.document(code)
        let snapshot = try await inviteRef.getDocument()
        guard snapshot.exists, let data = snapshot.data() else {
            throw LinkRepositoryError.inviteNotFound
        }
        let invite = try Self.decodeInvite(data)

        guard invite.ownerUid != supporterUid else {
            throw LinkRepositoryError.cannotAcceptOwnInvite
        }

        // A pair of people has one link. Checking here gives a clear error
        // instead of a generic "permission denied" from the rules.
        let existing = try await links
            .whereField("ownerUid", isEqualTo: invite.ownerUid)
            .whereField("supporterUid", isEqualTo: supporterUid)
            .limit(to: 1)
            .getDocuments()
        guard existing.isEmpty else {
            throw LinkRepositoryError.alreadyLinked
        }

        let link = SupporterLink(
            id: SupporterLink.activeId(ownerUid: invite.ownerUid, supporterUid: supporterUid),
            ownerUid: invite.ownerUid,
            supporterUid: supporterUid,
            ownerEmail: invite.ownerEmail,
            supporterEmail: supporterEmail,
            inviteCode: code,
            permission: invite.permission,
            status: .active
        )

        // One atomic batch: create the link and consume the invite. The rules
        // require both, so an invite can't be used twice.
        let linkData = try Self.encode(link)
        let batch = db.batch()
        batch.setData(linkData, forDocument: links.document(link.id))
        batch.deleteDocument(inviteRef)
        try await batch.commit()
        return link
    }

    func updatePermission(of link: SupporterLink, to permission: LinkPermission) async throws {
        try await reference(for: link).updateData(["permission": permission.rawValue])
    }

    func revoke(_ link: SupporterLink) async throws {
        try await reference(for: link).delete()
    }

    /// Pending invites live in `invites`; active links in `links`.
    private func reference(for link: SupporterLink) -> DocumentReference {
        switch link.status {
        case .pending: return invites.document(link.id)
        case .active: return links.document(link.id)
        }
    }

    // MARK: - Real-time observation

    func observeLinks(forUser uid: String) -> AnyPublisher<[SupporterLink], Error> {
        let pendingInvites = observe(invites.whereField("ownerUid", isEqualTo: uid)) { document in
            Self.decodePendingLink(from: document)
        }
        let supportersOfMine = observe(links.whereField("ownerUid", isEqualTo: uid)) { document in
            Self.decodeActiveLink(from: document)
        }
        let peopleISupport = observe(links.whereField("supporterUid", isEqualTo: uid)) { document in
            Self.decodeActiveLink(from: document)
        }

        return Publishers.CombineLatest3(pendingInvites, supportersOfMine, peopleISupport)
            .map { $0 + $1 + $2 }
            .eraseToAnyPublisher()
    }

    /// One snapshot listener per subscriber, removed on cancel or completion.
    private func observe(
        _ query: Query,
        decode: @escaping (QueryDocumentSnapshot) -> SupporterLink?
    ) -> AnyPublisher<[SupporterLink], Error> {
        Deferred { () -> AnyPublisher<[SupporterLink], Error> in
            let subject = PassthroughSubject<[SupporterLink], Error>()
            let registration = query.addSnapshotListener { snapshot, error in
                if let error {
                    subject.send(completion: .failure(error))
                    return
                }
                guard let snapshot else { return }
                subject.send(snapshot.documents.compactMap(decode))
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

    static func encode(_ invite: InviteDocument) throws -> [String: Any] {
        try Firestore.Encoder().encode(invite)
    }

    static func encode(_ link: SupporterLink) throws -> [String: Any] {
        try Firestore.Encoder().encode(link)
    }

    static func decodeInvite(_ data: [String: Any]) throws -> InviteDocument {
        try Firestore.Decoder().decode(InviteDocument.self, from: data)
    }

    /// Decodes an active link. The document ID is authoritative for `id`.
    static func decodeLink(_ data: [String: Any], id: String) throws -> SupporterLink {
        var data = data
        data["id"] = id
        return try Firestore.Decoder().decode(SupporterLink.self, from: data)
    }

    /// An invite presented as a pending `SupporterLink` (its `id` is the code).
    static func pendingLink(code: String, invite: InviteDocument) -> SupporterLink {
        SupporterLink(
            id: code,
            ownerUid: invite.ownerUid,
            ownerEmail: invite.ownerEmail,
            inviteCode: code,
            permission: invite.permission,
            status: .pending,
            createdAt: invite.createdAt
        )
    }

    private static func decodePendingLink(from document: QueryDocumentSnapshot) -> SupporterLink? {
        do {
            return pendingLink(code: document.documentID, invite: try decodeInvite(document.data()))
        } catch {
            logSkipped(document, error)
            return nil
        }
    }

    private static func decodeActiveLink(from document: QueryDocumentSnapshot) -> SupporterLink? {
        do {
            return try decodeLink(document.data(), id: document.documentID)
        } catch {
            logSkipped(document, error)
            return nil
        }
    }

    private static func logSkipped(_ document: QueryDocumentSnapshot, _ error: Error) {
        #if DEBUG
        print("[FirestoreLinkRepository] Skipping malformed document \(document.documentID): \(error)")
        #endif
    }
}
