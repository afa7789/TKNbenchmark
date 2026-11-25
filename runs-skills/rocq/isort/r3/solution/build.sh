#!/usr/bin/env bash
# Check every proof in this directory; exits non-zero if any proof is rejected.
set -euo pipefail
cd "$(dirname "$0")"
rocq c -w +deprecated ISort.v
