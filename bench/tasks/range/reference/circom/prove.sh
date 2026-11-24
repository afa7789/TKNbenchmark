#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
node build/range_js/generate_witness.js build/range_js/range.wasm "$1" build/witness.wtns >/dev/null
