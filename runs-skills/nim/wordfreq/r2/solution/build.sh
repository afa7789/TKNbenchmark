#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nim c -d:danger -d:lto --opt:speed --hints:off --nimcache:./.nimcache -o:./app wordfreq.nim
