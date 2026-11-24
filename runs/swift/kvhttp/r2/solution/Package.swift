// swift-tools-version:6.0
import PackageDescription

// build.sh compiles with swiftc directly; this manifest exists for IDE/SwiftPM users.
let package = Package(
    name: "kvhttp",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "kvhttp"),
    ]
)
