#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

if ! dotnet publish src/Calc.csproj -c Release -r osx-arm64 -o "$out" -p:PublishAot=true >&2; then
    echo "Native AOT publish failed; falling back to a self-contained single-file build." >&2
    rm -rf "$out"/*
    dotnet publish src/Calc.csproj -c Release -r osx-arm64 -o "$out" \
        -p:PublishAot=false -p:SelfContained=true -p:PublishSingleFile=true >&2
fi

cp "$out/app" ./app
chmod +x ./app
