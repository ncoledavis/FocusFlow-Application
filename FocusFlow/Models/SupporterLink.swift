import Foundation

/// A link between an ADHD user (owner) and a trusted supporter.
/// Mirrors `links/{linkId}` in Firestore.
struct SupporterLink: Codable, Identifiable, Equatable {
    var id: String

    /// The ADHD user who owns the task list.
    var ownerUid: String

    /// The supporter. Nil until an invite is accepted.
    var supporterUid: String?

    /// Invite code used by a supporter to accept the link.
    var inviteCode: String?

    var permission: LinkPermission
    var status: LinkStatus

    var createdAt: Date

    init(
        id: String,
        ownerUid: String,
        supporterUid: String? = nil,
        inviteCode: String? = nil,
        permission: LinkPermission = .view,
        status: LinkStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerUid = ownerUid
        self.supporterUid = supporterUid
        self.inviteCode = inviteCode
        self.permission = permission
        self.status = status
        self.createdAt = createdAt
    }
}
