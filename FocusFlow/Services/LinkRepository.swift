import Foundation
import Combine

/// Errors raised by `LinkRepository` implementations.
enum LinkRepositoryError: LocalizedError, Equatable {
    case inviteNotFound
    case cannotAcceptOwnInvite
    case alreadyLinked
    case linkNotFound

    var errorDescription: String? {
        switch self {
        case .inviteNotFound:
            return "That invite code wasn't found. It may have been used or cancelled."
        case .cannotAcceptOwnInvite:
            return "That's your own invite. Share it with the person you want to support you."
        case .alreadyLinked:
            return "You're already a supporter for this person. Ask them to change your permission instead."
        case .linkNotFound:
            return "That link no longer exists."
        }
    }
}

/// Persistence boundary for supporter links. Implemented by
/// `FirestoreLinkRepository` in production and `MockLinkRepository` for tests
/// and offline demos.
///
/// A "link" is either a pending invite or an active supporter link; both come
/// back as `SupporterLink`, told apart by `status`.
protocol LinkRepository {
    /// Creates a pending invite and returns it. Its `id` / `inviteCode` is the
    /// code to share.
    func createInvite(ownerUid: String, ownerEmail: String?, permission: LinkPermission) async throws -> SupporterLink

    /// Accepts an invite by its (normalized) code and returns the new active
    /// link. The invite is consumed, so a code works once.
    func acceptInvite(code: String, supporterUid: String, supporterEmail: String?) async throws -> SupporterLink

    /// Changes what a supporter (or a pending invite) is allowed to do.
    func updatePermission(of link: SupporterLink, to permission: LinkPermission) async throws

    /// Removes an active link (taking the supporter's access away) or cancels a
    /// pending invite.
    func revoke(_ link: SupporterLink) async throws

    /// Real-time stream of every link the user is part of: invites they've
    /// sent, supporters they have, and people they support. Values must be
    /// delivered on the main queue.
    func observeLinks(forUser uid: String) -> AnyPublisher<[SupporterLink], Error>
}
