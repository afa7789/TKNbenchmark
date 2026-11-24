#!/usr/bin/env bash
# Compiles the circuit (fetching any dependencies declared in Nargo.toml).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
nargo compile
