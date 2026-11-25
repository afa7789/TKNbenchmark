// swift-tools-version: 6.1
import PackageDescription

// build.sh drives swiftc directly (SwiftPM is not required to build); this manifest
// mirrors the same layout for editors and `swift test` where SwiftPM is available.
let package = Package(
    name: "kvhttp",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "KVServer", swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .executableTarget(name: "app", dependencies: ["KVServer"]),
        .testTarget(name: "KVServerTests", dependencies: ["KVServer"]),
    ]
)
