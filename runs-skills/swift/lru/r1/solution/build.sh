#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
# Invokes swiftc directly (mirroring the Package.swift layout) so the build
# does not depend on a working SwiftPM installation.
set -euo pipefail
cd "$(dirname "$0")"

out=.build/manual
rm -rf "$out"
mkdir -p "$out"

# The default SDK may be newer than the installed compiler supports; if so,
# fall back to the newest installed SDK that the compiler can use.
compiles() {
    echo 'let x = 1' | SDKROOT="${1:-}" swiftc -typecheck - >/dev/null 2>&1
}
if [[ -z "${SDKROOT:-}" ]] && ! compiles "" && command -v xcrun >/dev/null; then
    sdk_dir="$(dirname "$(xcrun --show-sdk-path)")"
    for sdk in $(ls -d "$sdk_dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
        if compiles "$sdk"; then
            export SDKROOT="$sdk"
            break
        fi
    done
fi

swiftc -O -wmo -parse-as-library \
    -module-name LRUCore \
    -emit-module -emit-module-path "$out/LRUCore.swiftmodule" \
    -emit-library -static -o "$out/libLRUCore.a" \
    Sources/LRUCore/*.swift

swiftc -O -wmo \
    -module-name app \
    -I "$out" -L "$out" -lLRUCore \
    Sources/app/main.swift \
    -o app
