// Why: transcription and export take minutes and die if iOS suspends the process. While the
// session is working the screen must not auto-lock, and a brief app switch must not kill the run.
// This is the honest extent of what a foreground app can do; there is no true background mode
// for speech or export, so the UI says "keep the app open" rather than pretending otherwise.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ActivityKeeper {
    #if canImport(UIKit)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    private(set) var isActive = false

    /// Keeps the screen on and requests background execution time when the app leaves the foreground.
    func setWorking(_ working: Bool) {
        guard working != isActive else { return }
        isActive = working
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = working
        if working {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "liveslice.pipeline") { [weak self] in
                self?.endBackgroundTask()
            }
        } else {
            endBackgroundTask()
        }
        #endif
    }

    #if canImport(UIKit)
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    #endif
}
