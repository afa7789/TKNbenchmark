#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

sources=(Sources/calc/*.swift)
flags=(-O -wmo -module-name calc)

# Prefer the default SDK; if it was produced by a newer compiler than the
# installed one, fall back to any installed SDK that this compiler accepts.
if swiftc "${flags[@]}" "${sources[@]}" -o app 2>/dev/null; then
    exit 0
fi

sdk_root="$(dirname "$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)")"
for sdk in $(ls -d "$sdk_root"/MacOSX*.sdk 2>/dev/null | sort -rV); do
    if swiftc "${flags[@]}" -sdk "$sdk" "${sources[@]}" -o app 2>/dev/null; then
        exit 0
    fi
done

# Nothing worked: rerun with the default SDK to surface the diagnostics.
swiftc "${flags[@]}" "${sources[@]}" -o app
