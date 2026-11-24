#!/usr/bin/env bash
# Builds an optimized, self-contained release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

dotnet publish src/Calc.csproj -c Release -o "$out" --nologo -v quiet
cp "$out/app" ./app
chmod +x ./app
