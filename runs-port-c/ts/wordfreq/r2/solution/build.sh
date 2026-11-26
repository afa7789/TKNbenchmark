#!/usr/bin/env bash
# Builds ./app: strips TypeScript types from src/main.ts into dist/main.mjs
# (so no transpilation happens at startup) and writes a small node launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist
node --input-type=module -e '
import { readFileSync, writeFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
const js = stripTypeScriptTypes(readFileSync("src/main.ts", "utf8"), { mode: "strip" });
writeFileSync("dist/main.mjs", js);
'
node --check dist/main.mjs

cat > app <<'LAUNCHER'
#!/bin/sh
exec node "$(dirname "$0")/dist/main.mjs" "$@"
LAUNCHER
chmod +x app
