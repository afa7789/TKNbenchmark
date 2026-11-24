#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
node build/sudoku_js/generate_witness.js build/sudoku_js/sudoku.wasm "$1" build/witness.wtns >/dev/null
