#!/usr/bin/env bash
# Builds an optimized native (AOT) release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

# Homebrew's .NET SDK links native AOT binaries against Homebrew libraries.
if command -v brew >/dev/null 2>&1; then
  for formula in openssl@3 brotli zstd; do
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [[ -n "$prefix" && -d "$prefix/lib" ]]; then
      export LIBRARY_PATH="$prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    fi
  done
fi

rm -rf publish
dotnet publish src/Calc/Calc.csproj -c Release -r osx-arm64 -o publish --nologo
cp publish/app ./app
