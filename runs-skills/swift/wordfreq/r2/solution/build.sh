#!/usr/bin/env bash
# Builds an optimized release binary at ./app using swiftc directly
# (mirrors the Package.swift layout: WordFreq library + app executable).
set -euo pipefail
cd "$(dirname "$0")"

# The default SDK may be newer than the installed compiler; prefer one that
# matches this toolchain (Swift 6.1 ships with the macOS 15.x SDKs).
if [[ -z "${SDKROOT:-}" ]]; then
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk \
               /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; do
        if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
    done
fi

out=.build/release-swiftc
rm -rf "$out"
mkdir -p "$out"

swiftc -O -wmo -parse-as-library \
    -module-name WordFreq \
    -emit-module -emit-module-path "$out/WordFreq.swiftmodule" \
    -emit-library -static -o "$out/libWordFreq.a" \
    Sources/WordFreq/*.swift

swiftc -O -wmo \
    -module-name app \
    -I "$out" -L "$out" -lWordFreq \
    -o app \
    Sources/app/main.swift
