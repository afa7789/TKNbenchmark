#!/usr/bin/env bash
# Builds an optimized, self-contained single-file release binary and places it at ./app.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

out_dir="$(pwd)/.build/publish"
rm -rf "$out_dir"

dotnet publish src/WordFreq.csproj \
  --configuration Release \
  --output "$out_dir" \
  -p:DebugType=none \
  -p:DebugSymbols=false \
  --runtime "$(dotnet --info | awk '/RID:/ {print $2; exit}')" \
  --nologo

cp "$out_dir/app" ./app
chmod +x ./app
