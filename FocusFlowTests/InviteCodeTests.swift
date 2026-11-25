import XCTest
@testable import FocusFlow

final class InviteCodeTests: XCTestCase {

    func testGeneratedCodesAreValid() {
        for _ in 0..<50 {
            let code = InviteCode.generate()
            XCTAssertEqual(code.count, InviteCode.length)
            XCTAssertTrue(InviteCode.isValid(code), code)
        }
    }

    func testGeneratedCodesAreDifferent() {
        let codes = Set((0..<200).map { _ in InviteCode.generate() })
        XCTAssertEqual(codes.count, 200)
    }

    func testAlphabetLeavesOutEasilyConfusedCharacters() {
        for confusing in ["0", "O", "1", "I", "L"] {
            XCTAssertFalse(InviteCode.alphabet.contains(Character(confusing)), confusing)
        }
        XCTAssertEqual(InviteCode.alphabet.count, 31)
    }

    func testNormalizingCleansUpWhatPeopleTypeOrPaste() {
        XCTAssertEqual(InviteCode.normalized("abcd-2345"), "ABCD2345")
        XCTAssertEqual(InviteCode.normalized("  ab cd 23 45 "), "ABCD2345")
        XCTAssertEqual(InviteCode.normalized("ab_cd.23/45\n"), "ABCD2345")
        XCTAssertEqual(InviteCode.normalized(""), "")
    }

    func testValidation() {
        XCTAssertTrue(InviteCode.isValid("ABCD2345"))
        XCTAssertFalse(InviteCode.isValid(""))
        XCTAssertFalse(InviteCode.isValid("ABCD234"), "Too short")
        XCTAssertFalse(InviteCode.isValid("ABCD23456"), "Too long")
        XCTAssertFalse(InviteCode.isValid("abcd2345"), "Must be normalized first")
        XCTAssertFalse(InviteCode.isValid("ABCD234O"), "O is not in the alphabet")
        XCTAssertFalse(InviteCode.isValid("ABCD-345"), "Hyphen is not part of the code")
    }

    func testFormattingGroupsTheCodeInTwo() {
        XCTAssertEqual(InviteCode.formatted("ABCD2345"), "ABCD-2345")
        XCTAssertEqual(InviteCode.formatted("SHORT"), "SHORT", "Wrong-length input is left alone")
    }

    func testFormattedCodeNormalizesBackToTheOriginal() {
        let code = InviteCode.generate()
        XCTAssertEqual(InviteCode.normalized(InviteCode.formatted(code)), code)
    }
}
