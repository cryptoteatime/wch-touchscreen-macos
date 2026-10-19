import XCTest
@testable import MacXeneonEdgeTouchDriverCore

final class DesktopRestorationTests: XCTestCase {
    func testRebootWindowIdentityAndLaunchGrace() throws {
        try exerciseDesktopRestoration { value, reason in XCTAssertTrue(value, reason) }
    }

    func testDisplayReadinessAndIndependentAppActivity() {
        exerciseDesktopLayoutReadiness { value, reason in XCTAssertTrue(value, reason) }
    }
}
