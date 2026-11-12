import Foundation
import OSLog

/// Quits iMCP Helper after a stretch with no HomeKit calls.
///
/// iMCP launches the helper again on the next Home call, so nothing has to keep it running.
/// It never quits while a call is in flight, or while the helper isn't paired,
/// because then its window shows the pairing code that the person needs.
@MainActor
enum IdleQuit {
    static let idleLimit: Duration = .seconds(15 * 60)

    /// Whether the helper is paired. Until it is, the helper stays open.
    static var isPaired = false

    private static let log = Logger.service("helper.idle")
    private static var lastActivity = ContinuousClock.now
    private static var callsInFlight = 0
    private static var watcher: Task<Void, Never>?

    static func start() {
        guard watcher == nil else { return }
        lastActivity = .now
        watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard isPaired, callsInFlight == 0, ContinuousClock.now - lastActivity >= idleLimit else { continue }
                log.info("No Home calls for 15 minutes; quitting. iMCP relaunches the helper when needed.")
                terminate()
                return
            }
        }
    }

    static func callStarted() {
        callsInFlight += 1
        lastActivity = .now
    }

    static func callEnded() {
        callsInFlight = max(0, callsInFlight - 1)
        lastActivity = .now
    }

    /// UIKit on Mac Catalyst has no API to quit, so this asks AppKit's shared application.
    private static func terminate() {
        let application = (NSClassFromString("NSApplication") as AnyObject?)?
            .perform(NSSelectorFromString("sharedApplication"))?
            .takeUnretainedValue() as? NSObject
        application?.perform(NSSelectorFromString("terminate:"), with: nil)
    }
}
