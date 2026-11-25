#!/usr/bin/env bash
# Builds an optimized native (AOT) release binary of wordfreq and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

# Homebrew's .NET SDK links NativeAOT binaries against libraries that live under the brew prefix.
if command -v brew >/dev/null 2>&1; then
  for formula in openssl@3 brotli zstd; do
    if prefix="$(brew --prefix "$formula" 2>/dev/null)" && [[ -d "$prefix/lib" ]]; then
      LIBRARY_PATH="$prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    fi
  done
  export LIBRARY_PATH
fi

out=".build/publish"
rm -rf "$out"
dotnet publish src/WordFreq/WordFreq.csproj -c Release -r osx-arm64 -o "$out" --nologo -v quiet
cp "$out/WordFreq" ./app
chmod +x ./app
