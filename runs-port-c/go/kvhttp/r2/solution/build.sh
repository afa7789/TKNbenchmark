#!/usr/bin/env bash
# Builds an optimized release binary at ./app. No third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app .
