// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WordFreq",
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .executableTarget(name: "app", path: "Sources"),
    ]
)
