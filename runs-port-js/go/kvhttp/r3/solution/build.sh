#!/usr/bin/env bash
# Builds an optimized release binary at ./app.
set -euo pipefail
cd "$(dirname "$0")"

command -v go >/dev/null || { echo "build.sh: go is required" >&2; exit 1; }
go mod download
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app .
