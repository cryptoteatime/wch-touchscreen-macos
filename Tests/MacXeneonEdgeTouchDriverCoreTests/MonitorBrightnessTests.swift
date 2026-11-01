import XCTest
@testable import MacXeneonEdgeTouchDriverCore

final class MonitorBrightnessTests: XCTestCase {
    func testRepliesWhileAppKitSuspendsNotifications() {
        exerciseBrightnessNotifications { value, reason in XCTAssertTrue(value, reason) }
    }
    func testLatestBrightnessWorkAndReconnectFences() {
        exerciseBrightnessWork { value, reason in XCTAssertTrue(value, reason) }
    }

    func testReconnectOverridesAndMacSynchronization() throws {
        try exerciseMonitorBrightness { value, reason in XCTAssertTrue(value, reason) }
    }
}
