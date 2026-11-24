#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

compile() {
    swiftc -O -wmo "$@" -o app Sources/main.swift
}

# Prefer the default SDK; if it was produced by a newer compiler than the
# installed swiftc, fall back to the newest installed SDK that works.
if compile 2>/dev/null; then
    exit 0
fi
for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk \
                    /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk \
                    2>/dev/null | sort -rV); do
    if compile -sdk "$sdk" 2>/dev/null; then
        exit 0
    fi
done
# Nothing worked: rerun the default build to surface its diagnostics.
compile
