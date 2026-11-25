#!/usr/bin/env bash
# Compiles the circuit (no external dependencies to fetch).
set -euo pipefail
cd "$(dirname "$0")"
nargo compile
