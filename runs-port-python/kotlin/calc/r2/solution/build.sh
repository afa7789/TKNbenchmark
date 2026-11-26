#!/usr/bin/env bash
# Build: compile the calculator into a self-contained jar and generate the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src -include-runtime -jvm-target 21 -d build/calc.jar 2>&1 | grep -v '^warning:' || true
test -s build/calc.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -cp "$dir/build/calc.jar" calc.CalcKt
LAUNCHER
chmod +x app
