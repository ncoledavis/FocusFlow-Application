import Foundation
import Combine

/// In-memory `LinkRepository` for tests, previews, and running the app before
/// Firebase is configured. Follows the same rules as the Firestore version:
/// an invite works once, you can't accept your own, and a pair of people has at
/// most one link.
final class MockLinkRepository: LinkRepository {

    /// Keyed by `SupporterLink.id`: invite code for pending, `activeId` for active.
    private let store = CurrentValueSubject<[String: SupporterLink], Never>([:])
    private let codeGenerator: () -> String

    /// When set, the next call throws this error instead of succeeding.
    var nextError: Error?

    /// - Parameter codeGenerator: Produces invite codes. Tests inject a fixed
    ///   sequence.
    init(codeGenerator: @escaping () -> String = InviteCode.generate) {
        self.codeGenerator = codeGenerator
    }

    func createInvite(ownerUid: String, ownerEmail: String?, permission: LinkPermission) async throws -> SupporterLink {
        try throwPendingError()
        let code = codeGenerator()
        let invite = SupporterLink(
            id: code,
            ownerUid: ownerUid,
            ownerEmail: ownerEmail,
            inviteCode: code,
            permission: permission,
            status: .pending
        )
        store.value[code] = invite
        return invite
    }

    func acceptInvite(code: String, supporterUid: String, supporterEmail: String?) async throws -> SupporterLink {
        try throwPendingError()
        guard let invite = store.value[code], invite.status == .pending else {
            throw LinkRepositoryError.inviteNotFound
        }
        guard invite.ownerUid != supporterUid else {
            throw LinkRepositoryError.cannotAcceptOwnInvite
        }
        let linkId = SupporterLink.activeId(ownerUid: invite.ownerUid, supporterUid: supporterUid)
        guard store.value[linkId] == nil else {
            throw LinkRepositoryError.alreadyLinked
        }

        let link = SupporterLink(
            id: linkId,
            ownerUid: invite.ownerUid,
            supporterUid: supporterUid,
            ownerEmail: invite.ownerEmail,
            supporterEmail: supporterEmail,
            inviteCode: code,
            permission: invite.permission,
            status: .active
        )
        var updated = store.value
        updated[code] = nil
        updated[linkId] = link
        store.value = updated
        return link
    }

    func updatePermission(of link: SupporterLink, to permission: LinkPermission) async throws {
        try throwPendingError()
        guard var stored = store.value[link.id] else { throw LinkRepositoryError.linkNotFound }
        stored.permission = permission
        store.value[link.id] = stored
    }

    func revoke(_ link: SupporterLink) async throws {
        try throwPendingError()
        guard store.value[link.id] != nil else { throw LinkRepositoryError.linkNotFound }
        store.value[link.id] = nil
    }

    func observeLinks(forUser uid: String) -> AnyPublisher<[SupporterLink], Error> {
        store
            .map { links in links.values.filter { $0.ownerUid == uid || $0.supporterUid == uid } }
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    private func throwPendingError() throws {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
    }
}
