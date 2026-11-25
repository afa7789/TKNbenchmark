#!/usr/bin/env bash
# Compile the circuit to target/range.json.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
nargo compile
