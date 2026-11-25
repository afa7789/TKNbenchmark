// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LRU",
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "AppCore", swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .executableTarget(name: "app", dependencies: ["AppCore"]),
    ]
)
