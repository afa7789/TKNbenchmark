#!/usr/bin/env bash
# Check all proofs; exits non-zero if Lean rejects any of them.
set -euo pipefail
cd "$(dirname "$0")"
lean Lists.lean
