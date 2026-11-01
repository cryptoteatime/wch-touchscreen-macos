import XCTest
@testable import MacXeneonEdgeTouchDriverCore

final class MonitorBrightnessTests: XCTestCase {
    func testLatestBrightnessWorkAndReconnectFences() {
        exerciseBrightnessWork { value, reason in XCTAssertTrue(value, reason) }
    }

    func testReconnectOverridesAndMacSynchronization() throws {
        try exerciseMonitorBrightness { value, reason in XCTAssertTrue(value, reason) }
    }
}
