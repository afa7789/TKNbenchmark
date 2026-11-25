// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WordFreq",
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "WordFreq"),
        .executableTarget(name: "app", dependencies: ["WordFreq"]),
        .testTarget(name: "WordFreqTests", dependencies: ["WordFreq"]),
    ]
)
