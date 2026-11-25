#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
# Invokes swiftc directly (mirroring the SwiftPM layout in Package.swift) so the
# build does not depend on a working SwiftPM installation.
set -euo pipefail
cd "$(dirname "$0")"

# The default SDK may be newer than the installed compiler; prefer an SDK
# built for Swift 6.1 (macOS 15.x) when one is available.
if [[ -z "${SDKROOT:-}" ]]; then
    sdk_dir="$(xcrun --show-sdk-platform-path 2>/dev/null || true)/Developer/SDKs"
    [[ -d "$sdk_dir" ]] || sdk_dir=/Library/Developer/CommandLineTools/SDKs
    for candidate in "$sdk_dir"/MacOSX15.5.sdk "$sdk_dir"/MacOSX15.4.sdk "$sdk_dir"/MacOSX15.sdk; do
        if [[ -d "$candidate" ]]; then
            export SDKROOT="$candidate"
            break
        fi
    done
fi

build_dir=.build/manual
rm -rf "$build_dir"
mkdir -p "$build_dir"

swiftc -O -wmo -parse-as-library \
    -module-name LRUCore \
    -emit-library -static \
    -emit-module -emit-module-path "$build_dir/LRUCore.swiftmodule" \
    -o "$build_dir/libLRUCore.a" \
    Sources/LRUCore/*.swift

swiftc -O -wmo \
    -module-name app \
    -I "$build_dir" -L "$build_dir" -lLRUCore \
    -o app \
    Sources/app/main.swift
