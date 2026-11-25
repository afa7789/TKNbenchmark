#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rocq c -w +deprecated ISort.v
