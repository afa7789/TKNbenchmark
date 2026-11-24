#!/usr/bin/env bash
# Check all proofs; exits non-zero if any proof fails.
set -euo pipefail
cd "$(dirname "$0")"
coqc ISort.v
