#!/usr/bin/env bash
# Builds ./app: strips TypeScript types ahead of time into dist/main.js and
# installs a small launcher that runs it with node.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist
node --no-warnings -e '
const { readFileSync, writeFileSync } = require("node:fs");
const { stripTypeScriptTypes } = require("node:module");
const src = readFileSync("src/main.ts", "utf8");
writeFileSync("dist/main.js", stripTypeScriptTypes(src, { mode: "strip" }));
'

cat > app <<'LAUNCHER'
#!/bin/sh
exec node "$(dirname "$0")/dist/main.js" "$@"
LAUNCHER
chmod +x app
