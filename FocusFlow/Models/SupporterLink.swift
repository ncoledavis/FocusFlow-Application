import Foundation

/// A link between an ADHD user (owner) and a trusted supporter.
///
/// A link is either a pending invite (`status == .pending`, no supporter yet) or
/// an active link. In Firestore these live in two collections (`invites` and
/// `links`); `LinkRepository` merges them so the rest of the app sees one type.
/// See `FirestoreLinkRepository` for the schema.
struct SupporterLink: Codable, Identifiable, Equatable {
    /// For a pending invite this is the invite code. For an active link it's
    /// `activeId(ownerUid:supporterUid:)`.
    var id: String

    /// The ADHD user who owns the task list.
    var ownerUid: String

    /// The supporter. Nil until an invite is accepted.
    var supporterUid: String?

    /// Shown in lists so people see an email instead of a UID. Copied onto the
    /// link when it's created; display only, never used for access decisions.
    var ownerEmail: String?
    var supporterEmail: String?

    /// The code the invite was (or is) shared with.
    var inviteCode: String?

    var permission: LinkPermission
    var status: LinkStatus

    var createdAt: Date

    init(
        id: String,
        ownerUid: String,
        supporterUid: String? = nil,
        ownerEmail: String? = nil,
        supporterEmail: String? = nil,
        inviteCode: String? = nil,
        permission: LinkPermission = .view,
        status: LinkStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerUid = ownerUid
        self.supporterUid = supporterUid
        self.ownerEmail = ownerEmail
        self.supporterEmail = supporterEmail
        self.inviteCode = inviteCode
        self.permission = permission
        self.status = status
        self.createdAt = createdAt
    }

    /// The document ID for an active link. It's derived from both UIDs so
    /// Firestore security rules can find it by path (rules can't run queries).
    /// Firebase UIDs never contain `_`, so the ID is unambiguous.
    static func activeId(ownerUid: String, supporterUid: String) -> String {
        "\(ownerUid)_\(supporterUid)"
    }

    /// What to call the owner in the UI.
    var ownerLabel: String { ownerEmail ?? "Unknown user" }

    /// What to call the supporter in the UI.
    var supporterLabel: String { supporterEmail ?? "Unknown user" }
}
