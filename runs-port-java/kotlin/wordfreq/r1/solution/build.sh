#!/usr/bin/env bash
# Builds the wordfreq application and installs a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build
kotlinc -nowarn -include-runtime -d build/wordfreq.jar $(find src/main/kotlin -name '*.kt')

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/build/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
