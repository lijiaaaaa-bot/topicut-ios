// Why: the iOS app entry point (ADR-0009). It is deliberately one line of behaviour: hand off to
// LiveSliceUI's bootstrap, which owns wiring and shows any startup failure on screen.

import LiveSliceUI
import SwiftUI

@main
struct LiveSliceApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrap.makeRootView()
        }
    }
}
