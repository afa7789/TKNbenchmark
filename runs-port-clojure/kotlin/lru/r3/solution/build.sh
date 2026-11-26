#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) at build/lru.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build

kotlinc src/main/kotlin -include-runtime -d build/lru.jar 2>&1 | grep -v '^warning:' || true
[[ -f build/lru.jar ]] || { echo "build failed" >&2; exit 1; }

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$dir/build/lru.jar" "$@"
LAUNCHER
chmod +x app
