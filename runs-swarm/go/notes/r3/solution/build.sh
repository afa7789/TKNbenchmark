#!/usr/bin/env bash
# Builds the optimized release binary at ./app. The go tool fetches the dependencies pinned in go.sum.
set -euo pipefail
cd "$(dirname "$0")"
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o app ./cmd/notes
