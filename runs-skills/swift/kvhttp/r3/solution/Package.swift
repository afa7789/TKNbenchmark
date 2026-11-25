// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "kvhttp",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "KVHTTP", swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .executableTarget(name: "app", dependencies: ["KVHTTP"]),
        .testTarget(name: "KVHTTPTests", dependencies: ["KVHTTP"]),
    ]
)
