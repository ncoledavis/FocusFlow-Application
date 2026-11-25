import XCTest
@testable import FocusFlow

/// How links and invites map to and from Firestore documents. These run
/// without a network connection or a Firebase project. (What the security rules
/// allow is tested separately, in `firestore-tests/`.)
final class FirestoreLinkMappingTests: XCTestCase {

    private let created = Date(timeIntervalSince1970: 1_700_000_000.5)

    private func makeInvite(
        permission: LinkPermission = .add,
        email: String? = "owner@example.com"
    ) -> FirestoreLinkRepository.InviteDocument {
        FirestoreLinkRepository.InviteDocument(
            ownerUid: "owner",
            ownerEmail: email,
            permission: permission,
            createdAt: created
        )
    }

    private func makeLink() -> SupporterLink {
        SupporterLink(
            id: "owner_helper",
            ownerUid: "owner",
            supporterUid: "helper",
            ownerEmail: "owner@example.com",
            supporterEmail: "helper@example.com",
            inviteCode: "ABCD2345",
            permission: .edit,
            status: .active,
            createdAt: created
        )
    }

    // MARK: - Invites

    func testInviteRoundTrip() throws {
        let invite = makeInvite()

        let data = try FirestoreLinkRepository.encode(invite)
        let decoded = try FirestoreLinkRepository.decodeInvite(data)

        XCTAssertEqual(decoded, invite)
    }

    func testInviteStoresOnlyWhatTheRulesExpect() throws {
        let data = try FirestoreLinkRepository.encode(makeInvite(permission: .edit))

        XCTAssertEqual(Set(data.keys), ["ownerUid", "ownerEmail", "permission", "createdAt"])
        XCTAssertEqual(data["ownerUid"] as? String, "owner")
        XCTAssertEqual(data["permission"] as? String, "edit")
    }

    func testInviteWithoutAnEmailOmitsTheField() throws {
        let data = try FirestoreLinkRepository.encode(makeInvite(email: nil))

        XCTAssertNil(data["ownerEmail"])
    }

    func testAnInviteIsPresentedAsAPendingLinkKeyedByItsCode() {
        let link = FirestoreLinkRepository.pendingLink(code: "ABCD2345", invite: makeInvite(permission: .view))

        XCTAssertEqual(link.id, "ABCD2345")
        XCTAssertEqual(link.inviteCode, "ABCD2345")
        XCTAssertEqual(link.status, .pending)
        XCTAssertEqual(link.ownerUid, "owner")
        XCTAssertNil(link.supporterUid)
        XCTAssertEqual(link.permission, .view)
        XCTAssertEqual(link.createdAt, created)
    }

    // MARK: - Active links

    func testLinkRoundTrip() throws {
        let link = makeLink()

        let data = try FirestoreLinkRepository.encode(link)
        let decoded = try FirestoreLinkRepository.decodeLink(data, id: link.id)

        XCTAssertEqual(decoded, link)
    }

    func testLinkIncludesEveryFieldTheCreateRuleRequires() throws {
        let data = try FirestoreLinkRepository.encode(makeLink())

        for key in ["ownerUid", "supporterUid", "inviteCode", "permission", "status"] {
            XCTAssertNotNil(data[key], "Missing \(key)")
        }
        XCTAssertEqual(data["status"] as? String, "active")
        XCTAssertEqual(data["permission"] as? String, "edit")
        XCTAssertEqual(data["inviteCode"] as? String, "ABCD2345")
    }

    func testLinkStoresOnlyKnownFields() throws {
        let data = try FirestoreLinkRepository.encode(makeLink())

        let known: Set<String> = [
            "id", "ownerUid", "supporterUid", "ownerEmail", "supporterEmail",
            "inviteCode", "permission", "status", "createdAt"
        ]
        XCTAssertTrue(Set(data.keys).isSubset(of: known), "Unexpected: \(Set(data.keys).subtracting(known))")
    }

    func testDocumentIDIsAuthoritativeForTheLinksID() throws {
        var data = try FirestoreLinkRepository.encode(makeLink())
        data["id"] = "stale"

        let decoded = try FirestoreLinkRepository.decodeLink(data, id: "owner_helper")

        XCTAssertEqual(decoded.id, "owner_helper")
    }

    func testDecodingALinkWithAnUnknownPermissionThrows() throws {
        var data = try FirestoreLinkRepository.encode(makeLink())
        data["permission"] = "admin"

        XCTAssertThrowsError(try FirestoreLinkRepository.decodeLink(data, id: "owner_helper"))
    }

    // MARK: - IDs

    func testActiveLinkIDIsBuiltFromBothUIDs() {
        XCTAssertEqual(SupporterLink.activeId(ownerUid: "owner", supporterUid: "helper"), "owner_helper")
    }

    func testCollectionNamesMatchTheSecurityRules() {
        XCTAssertEqual(FirestoreLinkRepository.invitesCollection, "invites")
        XCTAssertEqual(FirestoreLinkRepository.linksCollection, "links")
    }
}
