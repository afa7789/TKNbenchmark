#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cc -std=c17 -O2 -DNDEBUG -Wall -Wextra -Wpedantic -o app src/main.c
