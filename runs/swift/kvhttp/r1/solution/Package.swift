// swift-tools-version:6.0
// Kept for editor/tooling support; build.sh compiles with swiftc directly.
import PackageDescription

let package = Package(
    name: "kvhttp",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "KVHTTP"
        ),
    ]
)
