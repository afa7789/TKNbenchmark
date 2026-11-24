#!/usr/bin/env bash
# Check all proofs; exits non-zero if any proof is rejected.
set -euo pipefail
cd "$(dirname "$0")"
lean ISort.lean
