#!/usr/bin/env bash
# Builds an optimized native (AOT) release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# Homebrew-installed SDKs need native dependency paths for the AOT linker.
if command -v brew >/dev/null 2>&1; then
  for lib in openssl@3 brotli zstd; do
    prefix="$(brew --prefix "$lib" 2>/dev/null || true)"
    [[ -n "$prefix" && -d "$prefix/lib" ]] && LIBRARY_PATH="$prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
  done
  export LIBRARY_PATH="${LIBRARY_PATH:-}"
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

dotnet publish src/WordFreq/WordFreq.csproj -c Release -r osx-arm64 -o "$out" --nologo -v quiet
cp "$out/app" ./app
chmod +x ./app
