#!/usr/bin/env bash
# Build the calc release binary and install it as ./app.
set -euo pipefail
cd "$(dirname "$0")"

export CGO_ENABLED=0
go build -trimpath -ldflags="-s -w" -o app .
