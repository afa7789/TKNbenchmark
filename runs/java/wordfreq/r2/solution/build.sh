#!/usr/bin/env bash
# Compiles the sources into build/app.jar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -encoding UTF-8 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class wordfreq.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
