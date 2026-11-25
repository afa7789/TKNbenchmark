#!/usr/bin/env bash
# Builds a self-contained release jar with kotlinc and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d build/app.jar -nowarn

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseParallelGC -cp "$dir/build/app.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
