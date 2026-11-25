#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

if ! dotnet publish src/Lru/Lru.csproj -c Release -r osx-arm64 -o "$out" -p:PublishAot=true --nologo; then
  echo "Native AOT publish failed; falling back to a self-contained single-file build." >&2
  rm -rf "$out"/*
  dotnet publish src/Lru/Lru.csproj -c Release -r osx-arm64 -o "$out" --self-contained \
    -p:PublishAot=false -p:PublishSingleFile=true -p:PublishReadyToRun=true --nologo
fi

cp "$out/app" ./app
chmod +x ./app
