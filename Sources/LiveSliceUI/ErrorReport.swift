// Why: TestFlight only auto-collects process crashes. Typed pipeline failures (`.failed`,
// `sliceError`) stay on screen — sharing the verbatim text + build lets a tester paste the
// problem into chat without retyping (ADR-0005: errors are information, not decoration).

import Foundation
import SwiftUI

public enum ErrorReport {
    /// One pasteable block: display name, marketing version, build, then the error as shown.
    public static func text(
        message: String,
        displayName: String,
        version: String,
        build: String
    ) -> String {
        let head: String
        if displayName.isEmpty {
            head = "\(version) (\(build))"
        } else {
            head = "\(displayName) \(version) (\(build))"
        }
        return "\(head)\n\(message)"
    }

    public static func text(message: String) -> String {
        let info = Bundle.main.infoDictionary
        let displayName: String
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            displayName = name
        } else if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
            displayName = name
        } else {
            displayName = ""
        }
        // Bundle keys are required in a real app Info.plist; missing them is labeled, not invented.
        let version: String
        if let value = info?["CFBundleShortVersionString"] as? String {
            version = value
        } else {
            version = "missing-version"
        }
        let build: String
        if let value = info?["CFBundleVersion"] as? String {
            build = value
        } else {
            build = "missing-build"
        }
        return text(message: message, displayName: displayName, version: version, build: build)
    }
}

struct ErrorShareButton: View {
    let message: String

    var body: some View {
        ShareLink(item: ErrorReport.text(message: message)) {
            Label("分享错误", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(QuietButtonStyle())
        .accessibilityLabel("分享错误")
    }
}
