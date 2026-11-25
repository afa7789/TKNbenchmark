#!/usr/bin/env bash
# Builds the wordfreq jar and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -encoding UTF-8 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class wordfreq.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -jar "$dir/build/app.jar" "$@"
LAUNCHER
chmod +x app
