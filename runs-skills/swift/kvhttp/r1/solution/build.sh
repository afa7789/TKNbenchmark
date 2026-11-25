#!/usr/bin/env bash
# Builds an optimized release binary at ./app using swiftc directly. The project has no
# third-party dependencies, so SwiftPM is not required.
set -euo pipefail
cd "$(dirname "$0")"

BUILD_DIR=.build/release-swiftc
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Command Line Tools installs can default to an SDK newer than the compiler understands.
# Probe the default SDK and fall back to the newest SDK the compiler can actually use.
sdk_works() {
    echo 'import Foundation' | swiftc -sdk "$1" -typecheck - >/dev/null 2>&1
}
if [[ -z "${SDKROOT:-}" ]]; then
    SDKROOT="$(xcrun --show-sdk-path)"
    if ! sdk_works "$SDKROOT"; then
        sdk_dir="$(dirname "$SDKROOT")"
        for candidate in $(ls -d "$sdk_dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
            if sdk_works "$candidate"; then SDKROOT="$candidate"; break; fi
        done
    fi
fi
export SDKROOT

FLAGS=(-sdk "$SDKROOT" -O -whole-module-optimization -swift-version 6)

swiftc "${FLAGS[@]}" -parse-as-library \
    -enable-upcoming-feature ExistentialAny \
    -module-name KVServer -emit-module -emit-module-path "$BUILD_DIR/KVServer.swiftmodule" \
    -emit-library -static -o "$BUILD_DIR/libKVServer.a" \
    Sources/KVServer/*.swift

swiftc "${FLAGS[@]}" -module-name app -I "$BUILD_DIR" -L "$BUILD_DIR" -lKVServer \
    Sources/app/main.swift -o app
