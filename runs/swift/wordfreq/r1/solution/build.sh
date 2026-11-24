#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

sources=(Sources/wordfreq/*.swift)
flags=(-O -wmo)

# Prefer the default SDK; if it does not match the installed compiler
# (a common Command Line Tools mismatch), fall back to other installed SDKs.
if swiftc "${flags[@]}" "${sources[@]}" -o app 2>/dev/null; then
    exit 0
fi

sdk_root=$(dirname "$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)")
for sdk in $(ls -d "$sdk_root"/MacOSX*.sdk 2>/dev/null | sort -rV); do
    if swiftc "${flags[@]}" -sdk "$sdk" "${sources[@]}" -o app 2>/dev/null; then
        exit 0
    fi
done

# Nothing worked: rerun with the default SDK to surface the diagnostics.
swiftc "${flags[@]}" "${sources[@]}" -o app
