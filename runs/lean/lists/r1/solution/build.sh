#!/usr/bin/env bash
# Check all proofs: fails (non-zero exit) if Lean rejects Lists.lean.
set -euo pipefail
cd "$(dirname "$0")"
lean Lists.lean
