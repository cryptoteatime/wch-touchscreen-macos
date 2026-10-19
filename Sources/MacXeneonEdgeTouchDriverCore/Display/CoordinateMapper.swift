import CoreGraphics
import Foundation

/// Maps raw HID coordinates into Quartz display coordinates.
public struct CoordinateMapper: Equatable {
    /// Minimum raw X coordinate emitted by the touchscreen.
    public let rawMinX: Int

    /// Maximum raw X coordinate emitted by the touchscreen.
    public let rawMaxX: Int

    /// Minimum raw Y coordinate emitted by the touchscreen.
    public let rawMinY: Int

    /// Maximum raw Y coordinate emitted by the touchscreen.
    public let rawMaxY: Int

    /// Target display bounds in Quartz coordinates.
    public let displayBounds: CGRect

    /// Rotation of the assigned display, as reported by CoreGraphics.
    public let rotationDegrees: Int
    public let clampsToPixelInterior: Bool

    /// Creates a mapper for a raw coordinate range and target display bounds.
    public init(
        rawMinX: Int = XeneonEdgeDevice.rawXRange.lowerBound,
        rawMaxX: Int = XeneonEdgeDevice.rawXRange.upperBound,
        rawMinY: Int = XeneonEdgeDevice.rawYRange.lowerBound,
        rawMaxY: Int = XeneonEdgeDevice.rawYRange.upperBound,
        displayBounds: CGRect,
        rotationDegrees: Int = 0,
        clampsToPixelInterior: Bool = true
    ) {
        precondition(rawMaxX > rawMinX, "rawMaxX must be greater than rawMinX")
        precondition(rawMaxY > rawMinY, "rawMaxY must be greater than rawMinY")

        self.rawMinX = rawMinX
        self.rawMaxX = rawMaxX
        self.rawMinY = rawMinY
        self.rawMaxY = rawMaxY
        self.displayBounds = displayBounds
        self.rotationDegrees = ((rotationDegrees % 360) + 360) % 360
        self.clampsToPixelInterior = clampsToPixelInterior
    }

    /// Maps a raw touchscreen coordinate to the target display.
    public func map(rawX: Int, rawY: Int) -> CGPoint {
        let clampedX = clamp(rawX, lowerBound: rawMinX, upperBound: rawMaxX)
        let clampedY = clamp(rawY, lowerBound: rawMinY, upperBound: rawMaxY)

        let normalizedX = CGFloat(clampedX - rawMinX) / CGFloat(rawMaxX - rawMinX)
        let normalizedY = CGFloat(clampedY - rawMinY) / CGFloat(rawMaxY - rawMinY)

        let rotated: CGPoint
        switch rotationDegrees {
        case 90: rotated = CGPoint(x: 1 - normalizedY, y: normalizedX)
        case 180: rotated = CGPoint(x: 1 - normalizedX, y: 1 - normalizedY)
        case 270: rotated = CGPoint(x: normalizedY, y: 1 - normalizedX)
        default: rotated = CGPoint(x: normalizedX, y: normalizedY)
        }
        let point = CGPoint(x: displayBounds.minX + rotated.x * displayBounds.width,
                            y: displayBounds.minY + rotated.y * displayBounds.height)
        guard clampsToPixelInterior else { return point }
        // Quartz rectangles exclude their right/bottom edges. Keep a corner
        // touch inside its assigned display rather than on a neighbouring one.
        return CGPoint(
            x: min(point.x,
                   displayBounds.minX + max(0, displayBounds.width - 1)),
            y: min(point.y,
                   displayBounds.minY + max(0, displayBounds.height - 1))
        )
    }

    private func clamp(_ value: Int, lowerBound: Int, upperBound: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }
}
