#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
go mod download
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app .
