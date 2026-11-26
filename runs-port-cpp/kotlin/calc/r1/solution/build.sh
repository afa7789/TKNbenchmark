#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/calc.jar -nowarn
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$(dirname "$0")/build/calc.jar" "$@"
SH
chmod +x app
