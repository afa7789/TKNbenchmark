#!/usr/bin/env bash
# Builds an optimized release binary and places it at ./app.
#
# Invokes swiftc directly (rather than `swift build`) so the build does not
# depend on a working SwiftPM installation. Package.swift describes the same
# layout for use with SwiftPM and `swift test`.
set -euo pipefail
cd "$(dirname "$0")"

build_dir=.build/manual
rm -rf "$build_dir"
mkdir -p "$build_dir"

# The default SDK may have been built by a newer compiler than the installed
# swiftc; if so, fall back to an installed SDK whose stdlib interface matches.
sdk_args=()
if ! echo '' | swiftc -parse-as-library -typecheck - >/dev/null 2>&1; then
    compiler_version=$(swiftc --version 2>/dev/null | sed -n 's/.*(\(swiftlang-[^ ]*\).*/\1/p' | head -n1)
    for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk \
               /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk; do
        interface=$(ls "$sdk"/usr/lib/swift/Swift.swiftmodule/*.swiftinterface 2>/dev/null | head -n1 || true)
        if [[ -n "$interface" && -n "$compiler_version" ]] && grep -q "$compiler_version" "$interface"; then
            sdk_args=(-sdk "$sdk")
            break
        fi
    done
fi

swiftc -O -wmo -parse-as-library "${sdk_args[@]}" \
    -module-name WordFreqCore \
    -enable-upcoming-feature ExistentialAny \
    -emit-module -emit-module-path "$build_dir/WordFreqCore.swiftmodule" \
    -emit-library -static -o "$build_dir/libWordFreqCore.a" \
    Sources/WordFreqCore/*.swift

swiftc -O -wmo "${sdk_args[@]}" \
    -module-name app \
    -I "$build_dir" -L "$build_dir" -lWordFreqCore \
    -o ./app \
    Sources/app/*.swift
