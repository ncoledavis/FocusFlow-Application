import Foundation
import Combine

/// Persistence boundary for supporter links. Concrete implementation
/// (FirestoreLinkRepository) arrives in Task 6.
protocol LinkRepository {
    func createInvite(ownerUid: String, permission: LinkPermission) async throws -> SupporterLink
    func acceptInvite(code: String, supporterUid: String) async throws -> SupporterLink
    func updatePermission(linkId: String, permission: LinkPermission) async throws
    func revoke(linkId: String) async throws

    /// Real-time stream of links where the given user is owner or supporter.
    func observeLinks(forUser uid: String) -> AnyPublisher<[SupporterLink], Error>
}
