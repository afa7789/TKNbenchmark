#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

build() {
    swiftc -O -wmo "$@" Sources/main.swift -o app
}

# Try the default SDK first; if it was produced by a newer compiler than the
# installed one, fall back to any other installed macOS SDK that works.
if ! build 2>/dev/null; then
    for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -rV); do
        if build -sdk "$sdk" 2>/dev/null; then
            exit 0
        fi
    done
    build  # re-run to surface the original error
fi
