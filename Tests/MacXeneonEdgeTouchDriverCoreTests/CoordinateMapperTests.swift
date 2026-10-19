import CoreGraphics
import MacXeneonEdgeTouchDriverCore
import XCTest

final class CoordinateMapperTests: XCTestCase {
    func testMapsOrigin() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: 10, y: 20, width: 2_560, height: 720))

        XCTAssertEqual(mapper.map(rawX: 0, rawY: 0), CGPoint(x: 10, y: 20))
    }

    func testMapsMaximum() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: 10, y: 20, width: 2_560, height: 720))

        XCTAssertEqual(mapper.map(rawX: 16_383, rawY: 9_599), CGPoint(x: 2_569, y: 739))
    }

    func testMapsNegativeOriginDisplay() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: -1_280, y: 1_890, width: 2_560, height: 720))

        XCTAssertEqual(mapper.map(rawX: 0, rawY: 0), CGPoint(x: -1_280, y: 1_890))
        XCTAssertEqual(mapper.map(rawX: 16_383, rawY: 9_599), CGPoint(x: 1_279, y: 2_609))
    }

    func testClampsRawCoordinates() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: 0, y: 0, width: 2_560, height: 720))

        XCTAssertEqual(mapper.map(rawX: -500, rawY: -500), CGPoint(x: 0, y: 0))
        XCTAssertEqual(mapper.map(rawX: 99_999, rawY: 99_999), CGPoint(x: 2_559, y: 719))
    }

    func testMapsApproximateMidpoint() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: 0, y: 0, width: 2_560, height: 720))
        let point = mapper.map(rawX: 8_191, rawY: 4_799)

        XCTAssertEqual(point.x, 1_279.9218702318256, accuracy: 0.001)
        XCTAssertEqual(point.y, 359.962496093342, accuracy: 0.001)
    }

    func testPortraitLeftScreenCornersAt90Degrees() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: -1200, y: -1200, width: 1200, height: 1920), rotationDegrees: 90)
        XCTAssertEqual(mapper.map(rawX: 0, rawY: 0), CGPoint(x: -1, y: -1200))
        XCTAssertEqual(mapper.map(rawX: 0, rawY: 9599), CGPoint(x: -1200, y: -1200))
        XCTAssertEqual(mapper.map(rawX: 16383, rawY: 0), CGPoint(x: -1, y: 719))
    }

    func testPortraitRightScreenCornersAt270Degrees() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: 1512, y: -1009, width: 1200, height: 1920), rotationDegrees: 270)
        XCTAssertEqual(mapper.map(rawX: 0, rawY: 0), CGPoint(x: 1512, y: 910))
        XCTAssertEqual(mapper.map(rawX: 16383, rawY: 0), CGPoint(x: 1512, y: -1009))
        XCTAssertEqual(mapper.map(rawX: 0, rawY: 9599), CGPoint(x: 2711, y: 910))
    }

    func testEveryCornerStaysInsideItsDisplayAtEveryRotation() {
        let bounds = CGRect(x: -1200, y: -1200, width: 1200, height: 1920)
        for rotation in [0, 90, 180, 270, -90, 450] {
            let mapper = CoordinateMapper(displayBounds: bounds, rotationDegrees: rotation)
            for x in [-1, 0, 16383, 20000] {
                for y in [-1, 0, 9599, 20000] {
                    XCTAssertTrue(bounds.contains(mapper.map(rawX: x, rawY: y)), "rotation=\(rotation), x=\(x), y=\(y)")
                }
            }
        }
    }

    func testUnitSpacePairingCoordinatesAreNotPixelClamped() {
        let mapper = CoordinateMapper(displayBounds: CGRect(x: 0, y: 0, width: 1, height: 1), clampsToPixelInterior: false)
        let point = mapper.map(rawX: 8191, rawY: 4799)
        XCTAssertEqual(point.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(mapper.map(rawX: 16383, rawY: 9599), CGPoint(x: 1, y: 1))
    }
}
