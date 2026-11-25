#!/usr/bin/env bash
# Builds an optimized release binary of the LRU simulator at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
rm -rf build/publish
dotnet publish src/Lru.csproj -c Release -r osx-arm64 --self-contained \
  -p:PublishSingleFile=true -p:PublishReadyToRun=true \
  -o build/publish
cp build/publish/app ./app
chmod +x ./app
