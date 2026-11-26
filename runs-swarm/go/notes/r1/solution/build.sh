#!/usr/bin/env bash
# Builds the optimized release binary ./app. Dependencies are fetched by the
# go command (module cache) as needed.
set -euo pipefail
cd "$(dirname "$0")"

go mod download
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app ./cmd/notes
