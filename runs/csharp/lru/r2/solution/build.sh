#!/usr/bin/env bash
# Builds an optimized release binary of the LRU cache simulator at ./app.
set -euo pipefail

cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

out_dir="$(pwd)/.build/publish"
rm -rf "$out_dir"

dotnet publish src/Lru.csproj -c Release -o "$out_dir" -nologo

cp "$out_dir/app" ./app
chmod +x ./app
