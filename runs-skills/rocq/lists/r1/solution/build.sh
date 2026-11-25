#!/usr/bin/env bash
# Check every proof in Lists.v; fails on any error.
set -euo pipefail
cd "$(dirname "$0")"
rocq c Lists.v
