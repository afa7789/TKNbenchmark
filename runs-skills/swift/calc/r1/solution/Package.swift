// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Calc",
    products: [.executable(name: "app", targets: ["app"])],
    targets: [
        .target(name: "CalcCore", swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .executableTarget(name: "app", dependencies: ["CalcCore"]),
    ]
)
