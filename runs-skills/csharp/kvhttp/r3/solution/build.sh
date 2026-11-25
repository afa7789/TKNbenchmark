#!/usr/bin/env bash
# Builds an optimized, self-contained release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) rid=osx-arm64 ;;
  Darwin-x86_64) rid=osx-x64 ;;
  Linux-aarch64) rid=linux-arm64 ;;
  *) rid=linux-x64 ;;
esac

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
dotnet publish src/KvHttp/KvHttp.csproj -c Release -r "$rid" --self-contained \
  -p:PublishSingleFile=true -p:PublishReadyToRun=true -o out/publish
cp out/publish/KvHttp ./app
chmod +x ./app
