import XCTest
@testable import MacXeneonEdgeTouchDriverCore

final class DesktopRestorationTests: XCTestCase {
    func testClamshellAndDesktopTopologyLibrary() throws {
        try exerciseDesktopTopologies { value, reason in XCTAssertTrue(value, reason) }
    }

    func testRebootWindowIdentityAndLaunchGrace() throws {
        try exerciseDesktopRestoration { value, reason in XCTAssertTrue(value, reason) }
    }

    func testDisplayReadinessAndIndependentAppActivity() {
        exerciseDesktopLayoutReadiness { value, reason in XCTAssertTrue(value, reason) }
    }
}
