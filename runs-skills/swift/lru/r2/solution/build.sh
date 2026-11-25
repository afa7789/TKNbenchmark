#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
#
# Invokes swiftc directly so the build does not depend on SwiftPM; the
# sources follow the Package.swift layout (AppCore library + thin `app`
# executable), so `swift build` also works where SwiftPM is functional.
# If the default SDK was built by a newer compiler than the installed one,
# fall back to the newest installed SDK the compiler can actually use.
set -euo pipefail
cd "$(dirname "$0")"

build_dir=.build/manual
mkdir -p "$build_dir"

compile() {
    swiftc -O -wmo -cross-module-optimization -parse-as-library -module-name AppCore \
        -emit-library -static -emit-module \
        -emit-module-path "$build_dir/AppCore.swiftmodule" \
        -o "$build_dir/libAppCore.a" \
        "$@" Sources/AppCore/*.swift &&
    swiftc -O -wmo -cross-module-optimization -module-name app \
        -I "$build_dir" -L "$build_dir" -lAppCore \
        "$@" Sources/app/main.swift -o app
}

if compile 2>/dev/null; then
    exit 0
fi

sdk_root="$(dirname "$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)")"
for sdk in $(ls -d "$sdk_root"/MacOSX*.*.sdk 2>/dev/null | sort -t X -k 2 -V -r); do
    if compile -sdk "$sdk" 2>/dev/null; then
        exit 0
    fi
done

# Nothing worked: rerun with the default SDK to surface the diagnostics.
compile
