#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
cc -std=c17 -O2 -Wall -Wextra -pedantic -DNDEBUG -o app main.c
