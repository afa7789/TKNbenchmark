#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nim c -d:danger --opt:speed --hints:off --nimcache:./.nimcache -o:./app src/wordfreq.nim
