#!/usr/bin/env bash
# Check every proof in this directory with the Rocq compiler.
set -euo pipefail
cd "$(dirname "$0")"
coqc Lists.v
