#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Calc.kt -include-runtime -d build/calc.jar -nowarn
cat > app <<'SH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -cp "$DIR/build/calc.jar" calc.CalcKt "$@"
SH
chmod +x app
