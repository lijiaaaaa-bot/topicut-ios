// swift-tools-version: 6.2
// Why: single SwiftPM manifest; one library (LiveSliceCore), one real caller (liveslice-cli), one test target.
import PackageDescription

let package = Package(
    name: "liveslice-ios",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LiveSliceCore", targets: ["LiveSliceCore"]),
        .executable(name: "liveslice-cli", targets: ["liveslice-cli"]),
    ],
    targets: [
        .target(
            name: "LiveSliceCore",
            path: "Sources/LiveSliceCore"
        ),
        .executableTarget(
            name: "liveslice-cli",
            dependencies: ["LiveSliceCore"],
            path: "Sources/liveslice-cli"
        ),
        .testTarget(
            name: "LiveSliceCoreTests",
            dependencies: ["LiveSliceCore"],
            path: "Tests/LiveSliceCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
