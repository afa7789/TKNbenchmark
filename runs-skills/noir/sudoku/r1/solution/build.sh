#!/usr/bin/env bash
# Compiles the circuit to target/sudoku.json.
set -euo pipefail
cd "$(dirname "$0")"
nargo compile
