#!/usr/bin/env bash
# Runs the Swift Testing suite with swiftc (for toolchains where `swift test` is unavailable).
set -euo pipefail
cd "$(dirname "$0")"

SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
if ! echo 'import Foundation' | swiftc -sdk "$SDKROOT" -typecheck - >/dev/null 2>&1; then
    SDKROOT="$(ls -d "$(dirname "$SDKROOT")"/MacOSX15*.sdk | sort -rV | head -1)"
fi
FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
[[ -d "$FRAMEWORKS/Testing.framework" ]] || FRAMEWORKS="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks"

BUILD_DIR=.build/test-swiftc
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

swiftc -sdk "$SDKROOT" -swift-version 6 -enable-testing -parse-as-library \
    -module-name KVServer -emit-module -emit-module-path "$BUILD_DIR/KVServer.swiftmodule" \
    -emit-library -static -o "$BUILD_DIR/libKVServer.a" Sources/KVServer/*.swift

cat > "$BUILD_DIR/Runner.swift" <<'SWIFT'
import Testing
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
SWIFT

swiftc -sdk "$SDKROOT" -swift-version 6 -parse-as-library -F "$FRAMEWORKS" -framework Testing \
    -Xfrontend -disable-cross-import-overlays -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -I "$BUILD_DIR" -L "$BUILD_DIR" -lKVServer \
    Tests/KVServerTests/*.swift "$BUILD_DIR/Runner.swift" -o "$BUILD_DIR/tests"

"$BUILD_DIR/tests" "$@"
