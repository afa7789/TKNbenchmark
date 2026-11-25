#!/usr/bin/env bash
# Check every proof in this directory; exits non-zero if any proof fails.
set -euo pipefail
cd "$(dirname "$0")"
rocq c -w +deprecated Lists.v
if grep -nE '\b(Admitted|admit|Axiom|Parameter|Conjecture|give_up)\b' Lists.v; then
  echo "escape hatch found" >&2
  exit 1
fi
