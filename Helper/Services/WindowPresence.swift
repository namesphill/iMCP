import Foundation
import OSLog
import UIKit

/// Keeps iMCP Helper's window on screen, because HomeKit refuses accessory calls
/// (HMErrorDomain 80) while the app has no scene in the foreground.
///
/// Mac Catalyst moves a scene to the background when its window is closed,
/// minimized, or fully covered by other windows,
/// so a helper that sat behind other windows stops working after a while.
/// This brings the window back without activating the app,
/// so it doesn't take keyboard focus from whatever the person is using.
@MainActor
enum WindowPresence {
    private static let log = Logger.service("helper.window")

    static var hasForegroundScene: Bool {
        UIApplication.shared.connectedScenes.contains {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
    }

    /// Returns once a scene is in the foreground, or after `timeout`.
    /// With `force`, it shows the window even when a scene already reports the foreground,
    /// for when HomeKit refused a call anyway.
    static func ensureForeground(force: Bool = false, timeout: Duration = .seconds(2)) async {
        guard force || !hasForegroundScene else { return }
        let states = UIApplication.shared.connectedScenes.map { "\($0.activationState.rawValue)" }
        log.info(
            "Showing window (force: \(force, privacy: .public), scene states: \(states.joined(separator: ","), privacy: .public))."
        )

        if UIApplication.shared.connectedScenes.isEmpty {
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
        }
        orderFrontWithoutActivating()

        if force { try? await Task.sleep(for: .milliseconds(300)) }
        let deadline = ContinuousClock.now + timeout
        while !hasForegroundScene, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
            orderFrontWithoutActivating()
        }
        log.info("Foreground scene after showing window: \(hasForegroundScene, privacy: .public)")
    }

    /// Deminiaturizes and orders every AppKit window to the front without activating the app.
    /// UIKit on Mac Catalyst has no API for this, so it messages AppKit's windows directly.
    private static func orderFrontWithoutActivating() {
        guard let application = sharedApplication else { return }
        // A hidden app's windows stay hidden when ordered front.
        if (application.value(forKey: "isHidden") as? Bool) == true {
            application.perform(NSSelectorFromString("unhideWithoutActivation"))
        }
        for window in mainWindows {
            if (window.value(forKey: "isMiniaturized") as? Bool) == true {
                window.perform(NSSelectorFromString("deminiaturize:"), with: nil)
            }
            window.perform(NSSelectorFromString("orderFrontRegardless"))
        }
        placeInTopRightCorner()
    }

    /// Moves the window to the top-right corner of the primary display (the one with the menu bar),
    /// so it stays out of the way when it comes forward on its own.
    static func placeInTopRightCorner(margin: CGFloat = 12) {
        guard
            let screens = (NSClassFromString("NSScreen") as AnyObject?)?.value(forKey: "screens") as? [NSObject],
            let visible = (screens.first?.value(forKey: "visibleFrame") as? NSValue)?.cgRectValue
        else { return }
        for window in mainWindows {
            guard let frame = (window.value(forKey: "frame") as? NSValue)?.cgRectValue else { continue }
            // AppKit's origin is the bottom-left corner, and visibleFrame excludes the menu bar and Dock.
            let origin = CGPoint(x: visible.maxX - frame.width - margin, y: visible.maxY - frame.height - margin)
            guard frame.origin != origin else { continue }
            window.setValue(NSValue(cgPoint: origin), forKey: "frameOrigin")
        }
    }

    private static var sharedApplication: NSObject? {
        (NSClassFromString("NSApplication") as AnyObject?)?
            .perform(NSSelectorFromString("sharedApplication"))?
            .takeUnretainedValue() as? NSObject
    }

    private static var mainWindows: [NSObject] {
        let windows = sharedApplication?.value(forKey: "windows") as? [NSObject] ?? []
        return windows.filter { ($0.value(forKey: "canBecomeMainWindow") as? Bool) == true }
    }
}
