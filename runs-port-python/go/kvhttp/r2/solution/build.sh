#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export CGO_ENABLED=0
go build -trimpath -ldflags="-s -w" -o app .
