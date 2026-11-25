#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
#
# Invokes swiftc directly so the build does not depend on a working SwiftPM install.
# If the default SDK was built by a newer compiler than the installed swiftc, falls back
# to the newest installed macOS SDK that the compiler accepts.
set -euo pipefail
cd "$(dirname "$0")"

compile() {
    swiftc -O -wmo -module-name app Sources/*.swift -o app "$@"
}

if [[ -n "${SDKROOT:-}" ]]; then
    compile
    exit 0
fi
if compile 2>/dev/null; then
    exit 0
fi

sdk_dir="$(xcode-select -p)"
for dir in "$sdk_dir/SDKs" "$sdk_dir/Platforms/MacOSX.platform/Developer/SDKs"; do
    [[ -d "$dir" ]] || continue
    for sdk in $(ls -d "$dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
        if compile -sdk "$sdk" 2>/dev/null; then
            echo "built with SDK $sdk"
            exit 0
        fi
    done
done

# Nothing worked: rerun with the default SDK to surface the real error.
compile
