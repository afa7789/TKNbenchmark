#!/usr/bin/env bash
# Check every proof in this directory; exit non-zero if any is rejected.
set -euo pipefail
cd "$(dirname "$0")"
rocq c -w +deprecated ISort.v
