#!/usr/bin/env bash
# Builds an optimized native (AOT) release binary of the LRU simulator at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
out=_build/publish
rm -rf "$out"

if ! dotnet publish src/Lru/Lru.csproj -c Release -r osx-arm64 -o "$out" -p:PublishAot=true; then
  echo "AOT publish failed; falling back to a self-contained ReadyToRun build" >&2
  rm -rf "$out"
  dotnet publish src/Lru/Lru.csproj -c Release -r osx-arm64 -o "$out" \
    -p:PublishAot=false -p:SelfContained=true -p:PublishSingleFile=true -p:PublishReadyToRun=true
fi

cp "$out/app" ./app
chmod +x ./app
