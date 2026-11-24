#!/usr/bin/env bash
# Compiles the circuit to target/sudoku.json. No external dependencies.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
nargo compile
