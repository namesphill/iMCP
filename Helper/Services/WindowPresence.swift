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
        guard
            let application = (NSClassFromString("NSApplication") as AnyObject?)?
                .perform(NSSelectorFromString("sharedApplication"))?
                .takeUnretainedValue() as? NSObject,
            let windows = application.value(forKey: "windows") as? [NSObject]
        else { return }
        for window in windows {
            if (window.value(forKey: "isMiniaturized") as? Bool) == true {
                window.perform(NSSelectorFromString("deminiaturize:"), with: nil)
            }
            if (window.value(forKey: "canBecomeMainWindow") as? Bool) == true {
                window.perform(NSSelectorFromString("orderFrontRegardless"))
            }
        }
    }
}
