#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/calc.jar -nowarn
cat > app <<'SH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -Xss8m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$DIR/build/calc.jar"
SH
chmod +x app
