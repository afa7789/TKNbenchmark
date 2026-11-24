#!/usr/bin/env bash
# Builds the kvhttp server into build/kvhttp.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/kvhttp.jar --main-class kvhttp.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -Xshare:auto -jar "$DIR/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
