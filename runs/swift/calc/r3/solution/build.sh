#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

sources=(Sources/calc/*.swift)
compile() { swiftc -O -wmo "$@" -o app "${sources[@]}"; }

# Try the default SDK first. If it was built by a newer compiler than the
# installed swiftc, fall back to the other installed SDKs, newest first.
if compile 2>/dev/null; then
    exit 0
fi
sdk_root="$(dirname "$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)")"
for sdk in $(ls -d "$sdk_root"/MacOSX*.sdk 2>/dev/null | sort -rV); do
    if compile -sdk "$sdk" 2>/dev/null; then
        exit 0
    fi
done
# Nothing worked: rerun with the default SDK so the diagnostics are shown.
compile
