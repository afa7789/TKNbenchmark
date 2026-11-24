#!/usr/bin/env bash
# Builds the wordfreq application and installs a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/wordfreq.jar --main-class wordfreq.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
