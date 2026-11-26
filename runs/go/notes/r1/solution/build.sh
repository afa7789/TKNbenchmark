#!/usr/bin/env bash
# Builds an optimized release binary at ./app. Dependencies are fetched from the module proxy.
set -euo pipefail
cd "$(dirname "$0")"
export CGO_ENABLED=0
go mod download
go build -trimpath -ldflags="-s -w" -o app .
