#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
# Compiles with swiftc directly (no external dependencies), so it does not rely on SwiftPM.
set -euo pipefail
cd "$(dirname "$0")"

out=.build/release-swiftc
rm -rf "$out"
mkdir -p "$out"

# The Swift 6.1 compiler cannot read newer SDKs (e.g. macOS 26); prefer a macOS 15 SDK.
sdk="${SDKROOT:-}"
if [[ -z "$sdk" ]]; then
    sdk="$(xcrun --show-sdk-path)"
    sdk15="$(dirname "$sdk")/MacOSX15.sdk"
    [[ -d "$sdk15" ]] && sdk="$sdk15"
fi

flags=(-O -sdk "$sdk" -whole-module-optimization -swift-version 6 -target arm64-apple-macosx15.0)

swiftc "${flags[@]}" -parse-as-library -enable-upcoming-feature ExistentialAny \
    -module-name KVHTTP -emit-module -emit-module-path "$out/KVHTTP.swiftmodule" \
    -emit-library -static -o "$out/libKVHTTP.a" \
    Sources/KVHTTP/*.swift

swiftc "${flags[@]}" -I "$out" -L "$out" -lKVHTTP -framework Network \
    -module-name app -o ./app Sources/app/main.swift
