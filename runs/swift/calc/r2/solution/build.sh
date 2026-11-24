#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
#
# The default SDK may have been produced by a newer compiler than the installed
# toolchain, so fall back to other installed macOS SDKs if the first build fails.
set -euo pipefail
cd "$(dirname "$0")"

build() {
    swiftc -O -wmo "$@" -o app Sources/calc/*.swift
}

if build 2>/dev/null; then
    exit 0
fi

for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.*.sdk \
    /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk \
    2>/dev/null | sort -rV); do
    if build -sdk "$sdk" 2>/dev/null; then
        exit 0
    fi
done

# Nothing worked: rerun the default build so its diagnostics are shown.
build
