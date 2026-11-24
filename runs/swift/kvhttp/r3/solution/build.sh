#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
#
# The program depends only on the Swift standard library and Apple system
# frameworks, so it is compiled with swiftc directly (no package resolution).
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .build

# Command Line Tools installs can ship a default SDK newer than the installed
# compiler understands. Use the default SDK if it works; otherwise fall back to
# the newest installed macOS SDK the compiler accepts.
probe=.build/sdk-probe.swift
echo 'import Foundation' > "$probe"
sdk_args=()
if ! swiftc -typecheck "$probe" >/dev/null 2>&1; then
    sdk_dir="$(dirname "$(xcrun --show-sdk-path)")"
    found=""
    for sdk in $(ls -d "$sdk_dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -t X -k 3 -V -r); do
        if swiftc -sdk "$sdk" -typecheck "$probe" >/dev/null 2>&1; then
            found="$sdk"
            break
        fi
    done
    if [[ -z "$found" ]]; then
        echo "build.sh: no macOS SDK compatible with $(swiftc --version 2>&1 | head -1)" >&2
        exit 1
    fi
    echo "build.sh: using SDK $found" >&2
    sdk_args=(-sdk "$found")
fi

swiftc \
    "${sdk_args[@]}" \
    -O -wmo \
    -swift-version 6 \
    -module-name kvhttp \
    -o .build/kvhttp \
    Sources/kvhttp/*.swift
cp .build/kvhttp ./app
