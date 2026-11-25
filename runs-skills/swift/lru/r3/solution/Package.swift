// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LRU",
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "LRUCore"),
        .executableTarget(name: "app", dependencies: ["LRUCore"]),
        .testTarget(name: "LRUCoreTests", dependencies: ["LRUCore"]),
    ]
)
