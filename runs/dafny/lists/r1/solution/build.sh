#!/usr/bin/env bash
# Verify every proof in this directory; exits non-zero if any proof fails.
set -euo pipefail
cd "$(dirname "$0")"
dafny verify Lists.dfy
