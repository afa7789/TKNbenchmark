#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
rm -rf out
dotnet publish src/Lru.csproj -c Release -r osx-arm64 -o out --nologo
cp out/app ./app
chmod +x ./app
