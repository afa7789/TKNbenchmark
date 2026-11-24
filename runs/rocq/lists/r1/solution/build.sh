#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
coqc Lists.v
