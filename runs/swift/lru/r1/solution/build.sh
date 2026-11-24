#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

compile() {
    swiftc -O -wmo "$@" -o app Sources/*.swift
}

# Prefer the default SDK; if it was built by a newer compiler than the active
# toolchain, fall back to the newest installed SDK that the toolchain accepts.
if compile 2>/dev/null; then
    exit 0
fi
for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk 2>/dev/null | sort -Vr); do
    if compile -sdk "$sdk" 2>/dev/null; then
        exit 0
    fi
done
compile  # Re-run to surface the original diagnostics.
