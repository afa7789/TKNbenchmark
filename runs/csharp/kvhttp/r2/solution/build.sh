#!/usr/bin/env bash
# Builds an optimized release binary of the kvhttp server and places it at ./app.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

dotnet publish src/KvHttp/KvHttp.csproj \
  --configuration Release \
  --output "$out" \
  -p:PublishSingleFile=true \
  -p:SelfContained=true \
  -p:PublishReadyToRun=true \
  -p:UseCurrentRuntimeIdentifier=true \
  -p:DebugType=none

cp "$out/KvHttp" ./app
chmod +x ./app
