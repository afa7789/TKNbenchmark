#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/app.jar
cat > app <<'SH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xms256m -XX:+TieredCompilation -jar "$DIR/build/app.jar" "$@"
SH
chmod +x app
