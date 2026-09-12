// swift-tools-version: 6.2
// Why: single SwiftPM manifest. Core (decision), ASR (on-device speech), Render (AVFoundation),
// Keychain (API key), UI (SwiftUI screens + session) and the CLI. The iOS app target lives in
// project.yml (xcodegen) and consumes `LiveSliceUI`; every target here builds and tests on macOS.
// The chat client and LLM JSON extraction come from the shared LiJiaKit package (`LLMKit`),
// checked out as a sibling directory (ADR-0023).
import PackageDescription

let package = Package(
    name: "liveslice-ios",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LiveSliceCore", targets: ["LiveSliceCore"]),
        .library(name: "LiveSliceUI", targets: ["LiveSliceUI"]),
        .executable(name: "liveslice-cli", targets: ["liveslice-cli"]),
    ],
    dependencies: [
        .package(path: "../LiJiaKit"),
    ],
    targets: [
        .target(
            name: "LiveSliceCore",
            dependencies: [.product(name: "LLMKit", package: "LiJiaKit")],
            path: "Sources/LiveSliceCore"
        ),
        .target(name: "LiveSliceASR", dependencies: ["LiveSliceCore"], path: "Sources/LiveSliceASR"),
        .target(name: "LiveSliceRender", dependencies: ["LiveSliceCore"], path: "Sources/LiveSliceRender"),
        .target(name: "LiveSliceKeychain", path: "Sources/LiveSliceKeychain"),
        .target(
            name: "LiveSliceUI",
            dependencies: [
                "LiveSliceCore", "LiveSliceASR", "LiveSliceRender", "LiveSliceKeychain",
                .product(name: "LLMKit", package: "LiJiaKit"),
            ],
            path: "Sources/LiveSliceUI"
        ),
        .target(name: "LiveSliceTestSupport", path: "Sources/LiveSliceTestSupport"),
        .executableTarget(
            name: "liveslice-cli",
            dependencies: ["LiveSliceCore", .product(name: "LLMKit", package: "LiJiaKit")],
            path: "Sources/liveslice-cli"
        ),
        .testTarget(
            name: "LiveSliceCoreTests",
            dependencies: ["LiveSliceCore", .product(name: "LLMKit", package: "LiJiaKit")],
            path: "Tests/LiveSliceCoreTests"
        ),
        .testTarget(
            name: "LiveSliceASRTests",
            dependencies: ["LiveSliceASR", "LiveSliceTestSupport"],
            path: "Tests/LiveSliceASRTests"
        ),
        .testTarget(
            name: "LiveSliceRenderTests",
            dependencies: ["LiveSliceRender", "LiveSliceTestSupport"],
            path: "Tests/LiveSliceRenderTests"
        ),
        .testTarget(name: "LiveSliceKeychainTests", dependencies: ["LiveSliceKeychain"], path: "Tests/LiveSliceKeychainTests"),
        .testTarget(
            name: "LiveSliceUITests",
            dependencies: ["LiveSliceUI", .product(name: "LLMKit", package: "LiJiaKit")],
            path: "Tests/LiveSliceUITests"
        ),
        .testTarget(
            name: "LiveSliceTestSupportTests",
            dependencies: ["LiveSliceTestSupport"],
            path: "Tests/LiveSliceTestSupportTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
