#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
# Invokes swiftc directly (mirroring the SwiftPM layout in Package.swift) so the
# build does not depend on a working SwiftPM installation.
set -euo pipefail
cd "$(dirname "$0")"

# The default SDK may have been built by a newer compiler than the installed
# one; pick an SDK whose Swift interfaces match this compiler, if one exists.
if [[ -z "${SDKROOT:-}" && "$(uname)" == Darwin ]]; then
    compiler=$(swiftc --version 2>&1 | sed -n 's/.*(\(swiftlang-[^ ]*\).*/\1/p' | head -n1)
    default_sdk=$(xcrun --show-sdk-path)
    for sdk in "$default_sdk" "$(dirname "$default_sdk")"/MacOSX*.sdk; do
        if grep -qs -m1 "swift-compiler-version:.*$compiler" \
            "$sdk"/usr/lib/swift/Swift.swiftmodule/*.swiftinterface; then
            export SDKROOT="$sdk"
            break
        fi
    done
fi

build_dir=.build/release-swiftc
mkdir -p "$build_dir"

swiftc -O -wmo -parse-as-library \
    -module-name CalcCore -enable-upcoming-feature ExistentialAny \
    -emit-module -emit-module-path "$build_dir/CalcCore.swiftmodule" \
    -emit-library -static -o "$build_dir/libCalcCore.a" \
    Sources/CalcCore/*.swift

swiftc -O -wmo -module-name app \
    -I "$build_dir" -L "$build_dir" -lCalcCore \
    Sources/app/main.swift -o app
