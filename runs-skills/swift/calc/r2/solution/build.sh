#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
# Invokes swiftc directly (mirroring Package.swift's targets) so the build does
# not depend on SwiftPM being functional in the local toolchain.
set -euo pipefail
cd "$(dirname "$0")"

# Pick an SDK whose stdlib interface was produced by this exact compiler; a newer
# default SDK cannot be loaded by an older swiftc.
select_sdk() {
    local compiler sdk iface
    compiler=$(swiftc --version 2>&1 | sed -n 's/.*(\(swiftlang-[^ ]*\).*/\1/p' | head -n 1)
    [[ -n "$compiler" ]] || return 0
    for sdk in $(ls -d "$(xcrun --show-sdk-platform-path 2>/dev/null || echo /Library/Developer/CommandLineTools)"/../SDKs/MacOSX*.sdk \
                       /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV); do
        iface="$sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
        [[ -f "$iface" ]] || iface="$sdk/usr/lib/swift/Swift.swiftmodule/arm64-apple-macos.swiftinterface"
        if [[ -f "$iface" ]] && head -n 5 "$iface" | grep -q "$compiler"; then
            echo "$sdk"
            return 0
        fi
    done
}

sdk_flags=()
if [[ -z "${SDKROOT:-}" ]]; then
    sdk=$(select_sdk || true)
    [[ -n "$sdk" ]] && sdk_flags=(-sdk "$sdk")
fi

out=.build/release-swiftc
rm -rf "$out"
mkdir -p "$out"

swiftc ${sdk_flags[@]+"${sdk_flags[@]}"} -O -wmo -parse-as-library \
    -module-name CalcCore -emit-module -emit-module-path "$out/CalcCore.swiftmodule" \
    -emit-object -o "$out/CalcCore.o" \
    Sources/CalcCore/*.swift

swiftc ${sdk_flags[@]+"${sdk_flags[@]}"} -O -wmo -module-name app -I "$out" \
    Sources/app/*.swift "$out/CalcCore.o" -o ./app
