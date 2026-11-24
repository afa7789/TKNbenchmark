#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
#
# The project has no third-party dependencies, so swiftc is invoked directly;
# this avoids depending on a working SwiftPM install on the build machine.
set -euo pipefail
cd "$(dirname "$0")"

# "swiftlang-6.1.2.1.2" -> "6.1.2.1.2"
swiftlang_version() { grep -o 'swiftlang-[0-9.]*' | head -n1 | sed 's/swiftlang-//'; }

# Command Line Tools installs sometimes ship a default SDK built by a newer
# compiler than the installed one, which cannot load it. On macOS, pick the
# newest installed SDK whose stdlib interface this compiler can read.
pick_sdk() {
    local compiler default sdk_dir sdk built
    compiler="$(swiftc --version 2>&1 | swiftlang_version)"
    default="$(xcrun --show-sdk-path 2>/dev/null)" || return 0
    sdk_dir="$(dirname "$default")"
    for sdk in "$default" $(ls -d "$sdk_dir"/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r); do
        built="$(grep -h -m1 'swift-compiler-version' "$sdk"/usr/lib/swift/Swift.swiftmodule/*.swiftinterface 2>/dev/null | swiftlang_version)"
        if [[ -z "$compiler" || -z "$built" ]] || \
           [[ "$(printf '%s\n%s\n' "$built" "$compiler" | sort -V | tail -n1)" == "$compiler" ]]; then
            echo "$sdk"
            return 0
        fi
    done
}

sdk_args=()
if [[ "$(uname)" == "Darwin" ]]; then
    sdk="$(pick_sdk)"
    [[ -n "$sdk" ]] && sdk_args=(-sdk "$sdk")
fi

swiftc -O -wmo -swift-version 6 -module-name kvhttp "${sdk_args[@]}" Sources/kvhttp/*.swift -o app
