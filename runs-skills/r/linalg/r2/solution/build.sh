#!/usr/bin/env bash
# Builds ./app: a launcher that runs the byte-compiled linalg program with Rscript.
set -euo pipefail
cd "$(dirname "$0")"

Rscript --vanilla -e 'compiler::cmpfile("linalg.R", "linalg.Rc", options = list(optimize = 3))' >/dev/null

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec Rscript --vanilla -e "invisible(compiler::loadcmp('$dir/linalg.Rc'))"
LAUNCHER
chmod +x app
