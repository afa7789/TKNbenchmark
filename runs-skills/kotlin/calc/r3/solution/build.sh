#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Main.kt -include-runtime -jvm-target 21 -d build/app.jar
cat > app <<'SH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$DIR/build/app.jar" "$@"
SH
chmod +x app
