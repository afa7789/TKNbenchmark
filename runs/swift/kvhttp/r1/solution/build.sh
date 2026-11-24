#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
# The project has no third-party dependencies, so it compiles with swiftc directly.
set -euo pipefail
cd "$(dirname "$0")"

# Returns success if swiftc can import the standard library from the given SDK.
sdk_usable() {
    echo 'import Darwin' | swiftc -sdk "$1" -typecheck - >/dev/null 2>&1
}

# Pick an SDK the installed compiler can actually use. The default SDK may be
# newer than the compiler (mismatched Command Line Tools installs), so fall back
# to other installed macOS SDKs, newest first.
pick_sdk() {
    if [[ -n "${SDKROOT:-}" ]]; then
        echo "$SDKROOT"
        return
    fi
    local default
    default="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
    if [[ -n "$default" ]] && sdk_usable "$default"; then
        echo "$default"
        return
    fi
    local dir candidate
    for dir in "$(dirname "${default:-/Library/Developer/CommandLineTools/SDKs/x}")" \
               /Library/Developer/CommandLineTools/SDKs; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r candidate; do
            if sdk_usable "$candidate"; then
                echo "$candidate"
                return
            fi
        done < <(find "$dir" -maxdepth 1 -name 'MacOSX[0-9]*.sdk' -type d | sort -rV)
    done
    echo "error: no macOS SDK usable by $(swiftc --version 2>&1 | head -1)" >&2
    exit 1
}

SDK="$(pick_sdk)"
mkdir -p .build
swiftc -O -wmo -swift-version 6 \
    -sdk "$SDK" \
    -module-name KVHTTP \
    -o .build/app \
    Sources/KVHTTP/*.swift
mv .build/app ./app
