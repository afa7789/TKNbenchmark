#!/usr/bin/env bash
# Strips TypeScript types into plain JavaScript under dist/ and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf dist app
mkdir -p dist

node --input-type=module -e '
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
for (const file of readdirSync("src").filter((f) => f.endsWith(".ts"))) {
  const js = stripTypeScriptTypes(readFileSync(`src/${file}`, "utf8"), { mode: "strip" })
    .replace(/from (["\x27])(\.[^"\x27]*)\.ts\1/g, "from $1$2.js$1");
  writeFileSync(`dist/${file.replace(/\.ts$/, ".js")}`, js);
}
writeFileSync("dist/package.json", JSON.stringify({ type: "module" }) + "\n");
' 2> >(grep -v ExperimentalWarning >&2 || true)

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec node --disable-warning=ExperimentalWarning "$DIR/dist/main.js" "$@"
LAUNCHER
chmod +x app
