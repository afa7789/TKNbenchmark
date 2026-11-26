#!/usr/bin/env bash
# Build an optimized, stripped release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app .
