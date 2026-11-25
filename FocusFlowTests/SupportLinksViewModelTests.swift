import XCTest
@testable import FocusFlow

/// Invite, accept, change permission, and revoke, seen from both sides of a
/// link. Owners and supporters get their own view models over one shared
/// repository, the way two phones share Firestore.
@MainActor
final class SupportLinksViewModelTests: XCTestCase {

    private let alice = AppUser(id: "alice", email: "alice@example.com")
    private let bob = AppUser(id: "bob", email: "bob@example.com")
    private let carol = AppUser(id: "carol", email: "carol@example.com")

    private func makeViewModel(
        _ user: AppUser,
        repository: MockLinkRepository
    ) -> SupportLinksViewModel {
        let viewModel = SupportLinksViewModel(repository: repository, user: user)
        viewModel.start()
        return viewModel
    }

    /// A repository that hands out the given codes in order.
    private func makeRepository(codes: [String] = ["ABCD2345", "WXYZ6789", "KMNP2345"]) -> MockLinkRepository {
        var remaining = codes
        return MockLinkRepository(codeGenerator: { remaining.isEmpty ? InviteCode.generate() : remaining.removeFirst() })
    }

    // MARK: - Creating invites

    func testCreatingAnInviteShowsItAsPendingForTheOwnerOnly() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let other = makeViewModel(bob, repository: repository)

        let invite = await owner.createInvite(permission: .add)

        let created = try XCTUnwrap(invite)
        XCTAssertEqual(created.id, "ABCD2345")
        XCTAssertEqual(created.permission, .add)
        XCTAssertEqual(created.status, .pending)
        XCTAssertEqual(created.ownerEmail, "alice@example.com")
        XCTAssertEqual(owner.pendingInvites.map(\.id), ["ABCD2345"])
        XCTAssertEqual(owner.latestInvite?.id, "ABCD2345")
        XCTAssertTrue(other.links.isEmpty, "Someone else can't see the invite in their lists")
    }

    func testEachPermissionCanBeInvited() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)

        for permission in LinkPermission.allCases {
            await owner.createInvite(permission: permission)
        }

        XCTAssertEqual(Set(owner.pendingInvites.map(\.permission)), Set(LinkPermission.allCases))
    }

    func testCreatingAnInviteFailureSurfacesTheError() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        repository.nextError = WriteError()

        let invite = await owner.createInvite(permission: .view)

        XCTAssertNil(invite)
        XCTAssertEqual(owner.errorMessage, "write failed")
        XCTAssertNil(owner.latestInvite)
        XCTAssertTrue(owner.pendingInvites.isEmpty)
        XCTAssertFalse(owner.isWorking)
    }

    // MARK: - Accepting

    func testAcceptingMakesBothSidesSeeAnActiveLink() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .edit)

        let accepted = await supporter.acceptInvite(code: "ABCD2345")

        XCTAssertTrue(accepted)
        XCTAssertNil(supporter.errorMessage)

        let theirSupporter = try XCTUnwrap(owner.mySupporters.first)
        XCTAssertEqual(theirSupporter.supporterUid, "bob")
        XCTAssertEqual(theirSupporter.supporterLabel, "bob@example.com")
        XCTAssertEqual(theirSupporter.permission, .edit)
        XCTAssertTrue(owner.pendingInvites.isEmpty, "The invite is consumed")

        let supported = try XCTUnwrap(supporter.supportedOwners.first)
        XCTAssertEqual(supported.ownerUid, "alice")
        XCTAssertEqual(supported.ownerLabel, "alice@example.com")
        XCTAssertEqual(supported.permission, .edit)
        XCTAssertTrue(supporter.mySupporters.isEmpty)
    }

    func testAcceptingAcceptsTheCodeAsTyped() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)

        let accepted = await supporter.acceptInvite(code: "  abcd-2345 ")

        XCTAssertTrue(accepted)
        XCTAssertEqual(supporter.supportedOwners.count, 1)
    }

    func testAcceptingAMalformedCodeIsRefusedBeforeAskingTheRepository() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)

        let accepted = await supporter.acceptInvite(code: "123")

        XCTAssertFalse(accepted)
        XCTAssertEqual(supporter.errorMessage, "Invite codes are 8 letters and numbers, like ABCD-EFGH.")
        XCTAssertEqual(owner.pendingInvites.count, 1, "The invite is untouched")
    }

    func testAcceptingAnUnknownCodeSurfacesNotFound() async {
        let repository = makeRepository()
        let supporter = makeViewModel(bob, repository: repository)

        let accepted = await supporter.acceptInvite(code: "ZZZZ9999")

        XCTAssertFalse(accepted)
        XCTAssertEqual(supporter.errorMessage, LinkRepositoryError.inviteNotFound.errorDescription)
    }

    func testYouCannotAcceptYourOwnInvite() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        await owner.createInvite(permission: .view)

        let accepted = await owner.acceptInvite(code: "ABCD2345")

        XCTAssertFalse(accepted)
        XCTAssertEqual(owner.errorMessage, LinkRepositoryError.cannotAcceptOwnInvite.errorDescription)
        XCTAssertEqual(owner.pendingInvites.count, 1)
        XCTAssertTrue(owner.mySupporters.isEmpty)
    }

    func testACodeWorksOnlyOnce() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let first = makeViewModel(bob, repository: repository)
        let second = makeViewModel(carol, repository: repository)
        await owner.createInvite(permission: .view)
        await first.acceptInvite(code: "ABCD2345")

        let accepted = await second.acceptInvite(code: "ABCD2345")

        XCTAssertFalse(accepted)
        XCTAssertEqual(second.errorMessage, LinkRepositoryError.inviteNotFound.errorDescription)
        XCTAssertEqual(owner.mySupporters.map(\.supporterUid), ["bob"])
    }

    func testTwoPeopleHaveAtMostOneLink() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)
        await owner.createInvite(permission: .edit)
        await supporter.acceptInvite(code: "ABCD2345")

        let accepted = await supporter.acceptInvite(code: "WXYZ6789")

        XCTAssertFalse(accepted)
        XCTAssertEqual(supporter.errorMessage, LinkRepositoryError.alreadyLinked.errorDescription)
        XCTAssertEqual(owner.mySupporters.count, 1)
        XCTAssertEqual(owner.mySupporters.first?.permission, .view, "The existing link isn't replaced")
    }

    func testAcceptingFailureSurfacesTheError() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)
        struct NetworkError: LocalizedError { var errorDescription: String? { "offline" } }
        repository.nextError = NetworkError()

        let accepted = await supporter.acceptInvite(code: "ABCD2345")

        XCTAssertFalse(accepted)
        XCTAssertEqual(supporter.errorMessage, "offline")
        XCTAssertTrue(supporter.supportedOwners.isEmpty)
    }

    // MARK: - Changing permission

    func testChangingPermissionIsSeenByTheSupporterImmediately() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)
        await supporter.acceptInvite(code: "ABCD2345")
        let link = try XCTUnwrap(owner.mySupporters.first)

        let changed = await owner.updatePermission(of: link, to: .edit)

        XCTAssertTrue(changed)
        XCTAssertEqual(owner.mySupporters.first?.permission, .edit)
        XCTAssertEqual(supporter.supportedOwners.first?.permission, .edit)
        XCTAssertEqual(supporter.link(withId: link.id)?.permission, .edit)
    }

    func testPermissionOfAPendingInviteCanBeChanged() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        let created = await owner.createInvite(permission: .view)
        let invite = try XCTUnwrap(created)

        await owner.updatePermission(of: invite, to: .add)
        await supporter.acceptInvite(code: "ABCD2345")

        XCTAssertEqual(supporter.supportedOwners.first?.permission, .add, "The accepted link uses the updated permission")
    }

    func testChangingPermissionFailureSurfacesTheError() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)
        await supporter.acceptInvite(code: "ABCD2345")
        let link = try XCTUnwrap(owner.mySupporters.first)
        struct WriteError: LocalizedError { var errorDescription: String? { "write failed" } }
        repository.nextError = WriteError()

        let changed = await owner.updatePermission(of: link, to: .edit)

        XCTAssertFalse(changed)
        XCTAssertEqual(owner.errorMessage, "write failed")
        XCTAssertEqual(owner.mySupporters.first?.permission, .view)
    }

    // MARK: - Revoking

    func testRevokingRemovesAccessOnBothSides() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .edit)
        await supporter.acceptInvite(code: "ABCD2345")
        let link = try XCTUnwrap(owner.mySupporters.first)

        let revoked = await owner.revoke(link)

        XCTAssertTrue(revoked)
        XCTAssertTrue(owner.mySupporters.isEmpty)
        XCTAssertTrue(supporter.supportedOwners.isEmpty)
        XCTAssertNil(supporter.link(withId: link.id), "A screen showing this link can tell it's gone")
    }

    func testCancellingAnInviteStopsItWorking() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        let created = await owner.createInvite(permission: .view)
        let invite = try XCTUnwrap(created)

        await owner.revoke(invite)
        let accepted = await supporter.acceptInvite(code: "ABCD2345")

        XCTAssertTrue(owner.pendingInvites.isEmpty)
        XCTAssertNil(owner.latestInvite)
        XCTAssertFalse(accepted)
        XCTAssertEqual(supporter.errorMessage, LinkRepositoryError.inviteNotFound.errorDescription)
    }

    func testRevokingAMissingLinkSurfacesAnError() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let ghost = SupporterLink(id: "alice_ghost", ownerUid: "alice", supporterUid: "ghost", status: .active)

        let revoked = await owner.revoke(ghost)

        XCTAssertFalse(revoked)
        XCTAssertEqual(owner.errorMessage, LinkRepositoryError.linkNotFound.errorDescription)
    }

    func testARevokedSupporterNeedsANewInviteToComeBack() async throws {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        await owner.createInvite(permission: .view)
        await supporter.acceptInvite(code: "ABCD2345")
        let link = try XCTUnwrap(owner.mySupporters.first)
        await owner.revoke(link)

        let reusedOldCode = await supporter.acceptInvite(code: "ABCD2345")
        await owner.createInvite(permission: .view)
        let usedNewCode = await supporter.acceptInvite(code: "WXYZ6789")

        XCTAssertFalse(reusedOldCode)
        XCTAssertTrue(usedNewCode)
    }

    // MARK: - Both roles at once

    func testSomeoneCanBeAnOwnerAndASupporterAtTheSameTime() async {
        let repository = makeRepository()
        let aliceVM = makeViewModel(alice, repository: repository)
        let bobVM = makeViewModel(bob, repository: repository)
        let carolVM = makeViewModel(carol, repository: repository)

        await aliceVM.createInvite(permission: .view)
        await bobVM.acceptInvite(code: "ABCD2345")
        await carolVM.createInvite(permission: .add)
        await aliceVM.acceptInvite(code: "WXYZ6789")

        XCTAssertEqual(aliceVM.mySupporters.map(\.supporterUid), ["bob"])
        XCTAssertEqual(aliceVM.supportedOwners.map(\.ownerUid), ["carol"])
        XCTAssertEqual(bobVM.supportedOwners.map(\.ownerUid), ["alice"])
        XCTAssertEqual(carolVM.mySupporters.map(\.supporterUid), ["alice"])
    }

    func testUnrelatedPeopleSeeNothing() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        let supporter = makeViewModel(bob, repository: repository)
        let outsider = makeViewModel(carol, repository: repository)
        await owner.createInvite(permission: .view)
        await supporter.acceptInvite(code: "ABCD2345")
        await owner.createInvite(permission: .edit)

        XCTAssertTrue(outsider.links.isEmpty)
    }

    func testClearErrorResetsMessage() async {
        let repository = makeRepository()
        let supporter = makeViewModel(bob, repository: repository)
        await supporter.acceptInvite(code: "nope")
        XCTAssertNotNil(supporter.errorMessage)

        supporter.clearError()

        XCTAssertNil(supporter.errorMessage)
    }

    func testStartingTwiceDoesNotDuplicateLinks() async {
        let repository = makeRepository()
        let owner = makeViewModel(alice, repository: repository)
        owner.start()
        await owner.createInvite(permission: .view)

        XCTAssertEqual(owner.pendingInvites.count, 1)
    }
}
