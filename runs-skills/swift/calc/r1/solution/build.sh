#!/usr/bin/env bash
# Builds an optimized release binary at ./app using swiftc directly
# (mirrors the module layout described in Package.swift).
set -euo pipefail
cd "$(dirname "$0")"

out=.build/release-swiftc
rm -rf "$out"
mkdir -p "$out"

# Pick an SDK the installed compiler can actually use: the default one may have
# been built by a newer Swift than the active toolchain.
pick_sdk() {
    local probe="$out/probe.swift"
    echo 'print(0)' > "$probe"
    local candidates=()
    [[ -n "${SDKROOT:-}" ]] && candidates+=("$SDKROOT")
    candidates+=("$(xcrun --show-sdk-path 2>/dev/null || true)")
    local dir
    for dir in /Library/Developer/CommandLineTools/SDKs /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r sdk; do candidates+=("$sdk"); done < <(ls -d "$dir"/MacOSX*.sdk 2>/dev/null | sort -rV)
    done
    local sdk
    for sdk in "${candidates[@]}"; do
        [[ -n "$sdk" && -d "$sdk" ]] || continue
        if swiftc -sdk "$sdk" -typecheck "$probe" >/dev/null 2>&1; then
            echo "$sdk"
            return 0
        fi
    done
    echo "no usable macOS SDK found for $(swiftc --version 2>&1 | head -1)" >&2
    return 1
}

sdk=$(pick_sdk)

swiftc -sdk "$sdk" -O -wmo -parse-as-library \
    -enable-upcoming-feature ExistentialAny \
    -module-name CalcCore -emit-module -emit-module-path "$out/CalcCore.swiftmodule" \
    -emit-library -static -o "$out/libCalcCore.a" \
    Sources/CalcCore/*.swift

swiftc -sdk "$sdk" -O -wmo -module-name app \
    -I "$out" -L "$out" -lCalcCore \
    Sources/app/main.swift -o ./app
