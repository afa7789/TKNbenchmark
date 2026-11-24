#!/usr/bin/env bash
# Builds ./app: a launcher that runs the byte-compiled R program with Rscript.
set -euo pipefail
cd "$(dirname "$0")"

command -v Rscript >/dev/null || { echo "Rscript not found" >&2; exit 1; }
mkdir -p build
Rscript -e 'compiler::cmpfile("src/linalg.R", "build/linalg.Rc", options = list(optimize = 3))' >/dev/null

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec Rscript --vanilla -e 'compiler::loadcmp(commandArgs(trailingOnly = TRUE)[1L])' "$dir/build/linalg.Rc"
LAUNCHER
chmod +x app
