#!/usr/bin/env bash
# Builds a self-contained release jar and an ./app launcher. No third-party dependencies
# beyond the Kotlin standard library, which kotlinc bundles via -include-runtime.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -nowarn -d build/kvhttp.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -Xshare:auto -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
