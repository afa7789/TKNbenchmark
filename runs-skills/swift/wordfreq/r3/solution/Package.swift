// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WordFreq",
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(
            name: "WordFreqCore",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .executableTarget(name: "app", dependencies: ["WordFreqCore"]),
        .testTarget(name: "WordFreqCoreTests", dependencies: ["WordFreqCore"]),
    ]
)
