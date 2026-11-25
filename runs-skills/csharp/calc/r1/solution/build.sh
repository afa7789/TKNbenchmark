#!/usr/bin/env bash
# Builds an optimized native (AOT) release binary and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

# A Homebrew-installed SDK links NativeAOT binaries against Homebrew's native libraries.
if command -v brew >/dev/null 2>&1; then
  for lib in openssl@3 brotli zstd; do
    if prefix="$(brew --prefix "$lib" 2>/dev/null)" && [[ -d "$prefix/lib" ]]; then
      export LIBRARY_PATH="$prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    fi
  done
fi

publish_dir="$(mktemp -d)"
trap 'rm -rf "$publish_dir"' EXIT

dotnet publish src/Calc/Calc.csproj -c Release -r osx-arm64 -o "$publish_dir" --nologo
cp "$publish_dir/app" ./app
chmod +x ./app
