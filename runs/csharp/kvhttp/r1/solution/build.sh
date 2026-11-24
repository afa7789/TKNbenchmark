#!/usr/bin/env bash
# Builds an optimized release binary of kvhttp and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) rid=osx-arm64 ;;
  Darwin-x86_64) rid=osx-x64 ;;
  Linux-aarch64 | Linux-arm64) rid=linux-arm64 ;;
  *) rid=linux-x64 ;;
esac

rm -rf out
dotnet publish src/KvHttp/KvHttp.csproj -c Release -r "$rid" -o out --nologo -v quiet
ln -sfn out/KvHttp app
