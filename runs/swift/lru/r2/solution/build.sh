#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

sources=(Sources/lru/*.swift)
flags=(-O -wmo -o app)

# Prefer the default SDK; if it was built by a different compiler version,
# fall back to any installed SDK the active compiler can use.
if swiftc "${flags[@]}" "${sources[@]}" 2>/dev/null; then
    exit 0
fi
sdk_root="$(dirname "$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)")"
for sdk in $(ls -d "$sdk_root"/MacOSX*.sdk 2>/dev/null | sort -rV); do
    if swiftc -sdk "$sdk" "${flags[@]}" "${sources[@]}" 2>/dev/null; then
        exit 0
    fi
done
# Re-run with the default SDK to surface diagnostics.
swiftc "${flags[@]}" "${sources[@]}"
