#!/usr/bin/env bash
# Builds ./app: an optimized release binary of wordfreq.
set -euo pipefail
cd "$(dirname "$0")"

CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app .
