import Foundation
import CoreGraphics

/// Accessibility and CoreGraphics coordinates share a top-left screen origin.
/// Refuse stale, oversized, off-screen or left-application-menu coordinates.
enum MenuGeometry {
    struct StatusWindow: Equatable {
        var id: CGWindowID
        var pid: pid_t
        var frame: CGRect
    }

    // macOS can host another app's status item in Control Center; don't assume the app owns its window.
    static func statusWindow(for item: CGRect, owner: pid_t, hosts: Set<pid_t>, windows: [StatusWindow]) -> StatusWindow? {
        guard item.width > 0, item.width < 500, item.height > 0, item.height < 80 else { return nil }
        let center = CGPoint(x: item.midX, y: item.midY)
        let matches = windows.filter {
            ($0.pid == owner || hosts.contains($0.pid)) && $0.id != 0 &&
                $0.frame.width > 0 && $0.frame.width < 500 && $0.frame.height > 0 && $0.frame.height < 80 &&
                $0.frame.contains(center) && abs($0.frame.midX - item.midX) < 8 &&
                abs($0.frame.width - item.width) < 24
        }
        return matches.count == 1 ? matches[0] : nil
    }

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
