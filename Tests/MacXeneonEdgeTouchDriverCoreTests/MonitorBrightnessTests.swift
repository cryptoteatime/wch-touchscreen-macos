import XCTest
@testable import MacXeneonEdgeTouchDriverCore

final class MonitorBrightnessTests: XCTestCase {
    func testReconnectOverridesAndMacSynchronization() throws {
        try exerciseMonitorBrightness { value, reason in XCTAssertTrue(value, reason) }
    }
}
