#!/usr/bin/env bash
# Builds an optimized release binary at ./app. Dependencies are fetched from
# the module proxy as pinned in go.mod/go.sum.
set -euo pipefail
cd "$(dirname "$0")"

export CGO_ENABLED=0 # the SQLite driver is pure Go
go mod download
go build -trimpath -ldflags="-s -w" -o app .
