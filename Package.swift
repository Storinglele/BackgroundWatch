// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BackgroundWatch",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BackgroundWatch", targets: ["BackgroundWatch"])],
    targets: [
        .target(name: "BackgroundWatchCore"),
        .executableTarget(name: "BackgroundWatch", dependencies: ["BackgroundWatchCore"], resources: [.process("Resources")]),
        // XCTest ships with Xcode, not with the Command Line Tools, so the suite is a
        // plain executable: `swift run BackgroundWatchTests` works wherever Swift does.
        .executableTarget(name: "BackgroundWatchTests", dependencies: ["BackgroundWatchCore"]),
    ]
)
