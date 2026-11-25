import XCTest
@testable import FocusFlow

final class SupporterLinkTests: XCTestCase {

    func testJSONRoundTripKeepsEmails() throws {
        let link = SupporterLink(
            id: "owner_helper",
            ownerUid: "owner",
            supporterUid: "helper",
            ownerEmail: "owner@example.com",
            supporterEmail: "helper@example.com",
            inviteCode: "ABCD2345",
            permission: .add,
            status: .active,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(SupporterLink.self, from: encoder.encode(link))

        XCTAssertEqual(decoded, link)
    }

    func testLabelsFallBackWhenThereIsNoEmail() {
        let link = SupporterLink(id: "x", ownerUid: "owner")

        XCTAssertEqual(link.ownerLabel, "Unknown user")
        XCTAssertEqual(link.supporterLabel, "Unknown user")
    }

    func testLabelsUseTheEmailWhenThereIsOne() {
        let link = SupporterLink(
            id: "x", ownerUid: "owner", ownerEmail: "owner@example.com", supporterEmail: "helper@example.com"
        )

        XCTAssertEqual(link.ownerLabel, "owner@example.com")
        XCTAssertEqual(link.supporterLabel, "helper@example.com")
    }

    func testEveryPermissionHasATitleAndSummary() {
        for permission in LinkPermission.allCases {
            XCTAssertFalse(permission.title.isEmpty)
            XCTAssertFalse(permission.summary.isEmpty)
        }
        XCTAssertEqual(Set(LinkPermission.allCases.map(\.title)).count, 3)
    }
}
