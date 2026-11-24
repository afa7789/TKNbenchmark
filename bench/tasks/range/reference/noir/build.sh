#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nargo compile --silence-warnings >/dev/null
