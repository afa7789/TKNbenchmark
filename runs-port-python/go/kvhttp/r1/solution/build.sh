#!/usr/bin/env bash
# Build an optimized kvhttp release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export CGO_ENABLED=0
go mod download
go build -trimpath -ldflags="-s -w" -o app .
