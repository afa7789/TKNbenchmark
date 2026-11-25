// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "kvhttp",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "KVServer", swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .executableTarget(name: "app", dependencies: ["KVServer"]),
    ]
)
