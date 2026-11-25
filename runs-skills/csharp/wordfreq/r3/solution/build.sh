#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

out=build/publish

# Homebrew-installed SDKs need these native libraries on the linker path for Native AOT.
if command -v brew >/dev/null 2>&1; then
  for lib in openssl@3 brotli zstd; do
    prefix=$(brew --prefix "$lib" 2>/dev/null || true)
    [[ -n "$prefix" && -d "$prefix/lib" ]] && LIBRARY_PATH="$prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
  done
  export LIBRARY_PATH="${LIBRARY_PATH:-}"
fi
rm -rf "$out"
mkdir -p build
if ! dotnet publish src/WordFreq.csproj -c Release -r osx-arm64 -p:PublishAot=true -o "$out" >build/aot.log 2>&1; then
  echo "Native AOT publish failed; falling back to ReadyToRun single-file." >&2
  rm -rf "$out"
  dotnet publish src/WordFreq.csproj -c Release -r osx-arm64 --self-contained \
    -p:PublishSingleFile=true -p:PublishReadyToRun=true -o "$out"
fi
cp "$out/app" ./app
