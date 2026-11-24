#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cc -std=c17 -O2 -Wall -Wextra -Wpedantic -DNDEBUG -o app src/main.c
