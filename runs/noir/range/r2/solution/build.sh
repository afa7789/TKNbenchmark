#!/usr/bin/env bash
# Compiles the circuit. Requires nargo (>= 1.0.0) on PATH.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
nargo compile
