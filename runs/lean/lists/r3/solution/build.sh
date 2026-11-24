#!/usr/bin/env bash
# Check all proofs in Lists.lean; exits non-zero if any proof is rejected.
set -euo pipefail
cd "$(dirname "$0")"
lean Lists.lean
