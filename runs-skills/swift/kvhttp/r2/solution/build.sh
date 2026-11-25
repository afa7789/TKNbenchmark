#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
#
# The package has no third-party dependencies, so it is compiled with swiftc
# directly (module layout mirrors Package.swift). This avoids depending on a
# working SwiftPM install; `swift build -c release` is equivalent where it works.
set -euo pipefail
cd "$(dirname "$0")"

# Pick an SDK whose Swift interfaces were built by this compiler: the default
# SDK may be newer than the installed toolchain, which fails to import Swift.
select_sdk() {
    if [[ -n "${SDKROOT:-}" ]]; then
        echo "$SDKROOT"
        return
    fi
    local default tag sdk
    default="$(xcrun --show-sdk-path 2>/dev/null || true)"
    tag="$(swiftc --version 2>&1 | grep -o 'swiftlang-[0-9.]*' | head -n1)"
    for sdk in "$default" $(ls -d "$(dirname "${default:-/nonexistent}")"/MacOSX*.sdk 2>/dev/null | sort -rV); do
        local iface="$sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
        if [[ -n "$tag" && -f "$iface" ]] && head -n 5 "$iface" | grep -q -- "$tag"; then
            echo "$sdk"
            return
        fi
    done
    echo "$default"
}

out=.build/release-swiftc
rm -rf "$out"
mkdir -p "$out"

flags=(-O -wmo -swift-version 6 -enable-upcoming-feature ExistentialAny)
if [[ "$(uname)" == "Darwin" ]]; then
    flags+=(-sdk "$(select_sdk)" -target "$(uname -m)-apple-macosx15.0")
fi

swiftc "${flags[@]}" -parse-as-library -module-name KVServer \
    -emit-module -emit-module-path "$out/KVServer.swiftmodule" \
    -emit-library -static -o "$out/libKVServer.a" \
    Sources/KVServer/*.swift

swiftc "${flags[@]}" -module-name app -I "$out" -L "$out" -lKVServer \
    Sources/app/main.swift -o ./app
