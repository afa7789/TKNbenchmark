#!/usr/bin/env bash
# Check every proof in Lists.v; fail on any escape hatch.
set -euo pipefail
cd "$(dirname "$0")"
if sed -e 's/(\*.*\*)//g' Lists.v | grep -nE '\b(Admitted|admit|Axiom|Axioms|Parameter|Parameters|Conjecture|give_up)\b'; then
  echo "escape hatch found" >&2
  exit 1
fi
rocq c Lists.v
