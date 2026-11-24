#!/usr/bin/env bash
# Compiles the circuit to target/range.json.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
nargo compile
