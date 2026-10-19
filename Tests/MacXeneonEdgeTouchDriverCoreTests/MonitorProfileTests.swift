import XCTest
@testable import MacXeneonEdgeTouchDriverCore

final class MonitorProfileTests: XCTestCase {
    func testMixedDisplaysAndIndependentBrightnessProfiles() throws {
        try exerciseMonitorProfiles { value, reason in XCTAssertTrue(value, reason) }
    }
}
