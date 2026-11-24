#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

compile() {
    swiftc -O -wmo "$@" -o app Sources/*.swift
}

# Prefer the default SDK; if it does not match the installed compiler, fall
# back to the newest installed macOS SDK that does.
if compile 2>/dev/null; then
    exit 0
fi

sdk_root="/Library/Developer/CommandLineTools/SDKs"
if [[ -d "$sdk_root" ]]; then
    for sdk in $(ls -d "$sdk_root"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
        if compile -sdk "$sdk" 2>/dev/null; then
            exit 0
        fi
    done
fi

# Re-run with the default SDK so the real diagnostics are shown.
compile
