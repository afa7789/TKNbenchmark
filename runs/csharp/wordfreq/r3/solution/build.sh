#!/usr/bin/env bash
# Builds an optimized native release binary and places it at ./app.
set -euo pipefail

cd "$(dirname "$0")"

out_dir="$(mktemp -d)"
trap 'rm -rf "$out_dir"' EXIT

dotnet publish src/WordFreq.csproj -c Release -o "$out_dir" --nologo -v quiet
cp "$out_dir/app" ./app
chmod +x ./app
