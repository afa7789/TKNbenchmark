#!/usr/bin/env bash
# Build: Node.js runs the TypeScript sources directly, so just make the launcher
# executable and smoke-test it.
set -euo pipefail
cd "$(dirname "$0")"
chmod +x app
[[ "$(printf '1\nSET a 1\nGET a\n' | ./app)" == "1" ]]
