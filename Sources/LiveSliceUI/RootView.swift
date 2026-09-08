// Why: the app entry view. It owns the two long-lived objects (settings, session), shows the
// settings sheet, keeps the device awake while the session works, and turns a failed bootstrap
// (Keychain unreadable) into a visible error screen instead of a blank app.

import SwiftUI

struct RootView: View {
    @State private var settings: AppSettings
    @State private var session: SliceSession
    @State private var showSettings = false
    @State private var keeper = ActivityKeeper()

    init(settings: AppSettings, session: SliceSession) {
        _settings = State(initialValue: settings)
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            HomeView(session: session, settings: settings, openSettings: { showSettings = true })
                .studioBar()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if session.stage != .ready {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .disabled(session.isBusy)
                        }
                    }
                }
        }
        .tint(StudioTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
                .preferredColorScheme(.dark)
        }
        .onChange(of: session.isWorking, initial: true) { _, working in
            keeper.setWorking(working)
        }
        .sensoryFeedback(.success, trigger: session.stage == .ready) { _, ready in ready }
        .sensoryFeedback(.error, trigger: session.stage) { _, stage in
            if case .failed = stage { return true } else { return false }
        }
    }
}

/// Builds the root view with production wiring; a bootstrap failure is shown, never swallowed.
public enum AppBootstrap {
    @MainActor
    public static func makeRootView() -> AnyView {
        do {
            let settings = try AppSettings()
            let session = SliceSession(
                settings: settings, dependencies: .live(), store: try ProjectStore.applicationSupport(),
                scratchDirectory: AppDirectories.scratch, outputDirectory: AppDirectories.renders
            )
            return AnyView(RootView(settings: settings, session: session))
        } catch {
            return AnyView(BootstrapErrorView(message: ErrorText.describe(error)))
        }
    }
}

struct BootstrapErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("无法启动", systemImage: "exclamationmark.triangle")
        } description: {
            Text("启动失败：\(message)")
        }
    }
}
