#!/usr/bin/env bash
# Builds an optimized, natively compiled release binary and places it at ./app.
set -euo pipefail

cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

out_dir="build/publish"
rm -rf "$out_dir"

dotnet publish src/Lru.csproj -c Release -o "$out_dir" --nologo -v quiet

cp "$out_dir/app" ./app
chmod +x ./app
