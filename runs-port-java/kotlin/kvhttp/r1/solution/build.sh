#!/usr/bin/env bash
# Builds kvhttp into build/kvhttp.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc -Werror -jvm-target 21 -include-runtime -d build/kvhttp.jar $(find src/main/kotlin -name '*.kt')

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -jar "$dir/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
