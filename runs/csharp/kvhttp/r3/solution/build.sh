#!/usr/bin/env bash
# Builds an optimized release binary of kvhttp and places it at ./app.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

out_dir="$(mktemp -d)"
trap 'rm -rf "$out_dir"' EXIT

dotnet publish src/KvHttp/KvHttp.csproj \
  --configuration Release \
  --use-current-runtime \
  --self-contained true \
  -p:PublishSingleFile=true \
  -p:DebugType=none \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  --output "$out_dir"

rm -f ./app
cp "$out_dir/app" ./app
chmod +x ./app
