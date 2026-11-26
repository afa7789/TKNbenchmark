#!/usr/bin/env bash
# Builds the server jar and a launcher at ./app. Requires kotlinc and a JDK 21+; no third-party dependencies.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc -jvm-target 21 -include-runtime -nowarn -d build/kvhttp.jar $(find src/main/kotlin -name '*.kt')

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
# Launches the kvhttp server. Usage: ./app <port>
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/}java"
exec "$java_bin" -XX:+UseSerialGC -Xshare:auto -jar "$dir/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
