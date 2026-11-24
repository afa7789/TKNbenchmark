#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(Object.entries(j).map(([k,v])=>k+" = "+JSON.stringify(Array.isArray(v)?v.map(String):String(v))).join("\n"))' "$1" > Prover.toml
nargo execute --silence-warnings >/dev/null 2>&1
