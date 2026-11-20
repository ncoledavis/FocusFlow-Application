import XCTest
@testable import FocusFlow

final class CountdownFormatterTests: XCTestCase {

    func testClockStringUnderAnHour() {
        XCTAssertEqual(CountdownFormatter.clockString(for: 754), "12:34")
        XCTAssertEqual(CountdownFormatter.clockString(for: 60), "01:00")
        XCTAssertEqual(CountdownFormatter.clockString(for: 5), "00:05")
    }

    func testClockStringFromOneHourUp() {
        XCTAssertEqual(CountdownFormatter.clockString(for: 3_600), "1:00:00")
        XCTAssertEqual(CountdownFormatter.clockString(for: 3_725), "1:02:05")
    }

    func testClockStringRoundsPartialSecondsUp() {
        // Reads 00:01 until the moment time is actually up.
        XCTAssertEqual(CountdownFormatter.clockString(for: 0.4), "00:01")
        XCTAssertEqual(CountdownFormatter.clockString(for: 59.2), "01:00")
    }

    func testClockStringShowsOvertimeWithPlusSign() {
        XCTAssertEqual(CountdownFormatter.clockString(for: -135), "+02:15")
        XCTAssertEqual(CountdownFormatter.clockString(for: -3_725), "+1:02:05")
    }

    func testClockStringAtTheDeadlineShowsZero() {
        XCTAssertEqual(CountdownFormatter.clockString(for: 0), "00:00")
        XCTAssertEqual(CountdownFormatter.clockString(for: -0.4), "00:00")
        XCTAssertEqual(CountdownFormatter.clockString(for: -0.9), "00:00")
    }

    func testIsOvertime() {
        XCTAssertFalse(CountdownFormatter.isOvertime(1))
        XCTAssertTrue(CountdownFormatter.isOvertime(0))
        XCTAssertTrue(CountdownFormatter.isOvertime(-1))
    }

    func testSpokenStringWhileTimeRemains() {
        let spoken = CountdownFormatter.spokenString(for: 90)
        XCTAssertTrue(spoken.hasSuffix("remaining"), spoken)
        XCTAssertTrue(spoken.contains("30"), spoken)
    }

    func testSpokenStringWhenTimeIsUp() {
        XCTAssertEqual(CountdownFormatter.spokenString(for: 0), "Time is up")

        let overtime = CountdownFormatter.spokenString(for: -135)
        XCTAssertTrue(overtime.hasPrefix("Time is up"), overtime)
        XCTAssertTrue(overtime.hasSuffix("over"), overtime)
    }

    func testAllotmentString() {
        XCTAssertTrue(CountdownFormatter.allotmentString(for: 25 * 60).contains("25"))
        XCTAssertTrue(CountdownFormatter.allotmentString(for: 90 * 60).contains("1"))
    }
}
