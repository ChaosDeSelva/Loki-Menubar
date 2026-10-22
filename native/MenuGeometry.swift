import Foundation
import CoreGraphics

/// Accessibility and CoreGraphics coordinates share a top-left screen origin.
/// Refuse stale, oversized, off-screen or left-application-menu coordinates.
enum MenuGeometry {
    static func isSafe(_ rectangle: CGRect, on displays: [CGRect]) -> Bool {
        guard rectangle.minX.isFinite, rectangle.minY.isFinite,
              rectangle.width.isFinite, rectangle.height.isFinite,
              rectangle.width > 0, rectangle.width < 500,
              rectangle.height > 0, rectangle.height < 80 else { return false }
        return displays.contains { bounds in
            rectangle.minY >= bounds.minY && rectangle.maxY <= bounds.minY + 80 &&
                rectangle.minX >= bounds.minX + 120 && rectangle.maxX <= bounds.maxX
        }
    }
}
