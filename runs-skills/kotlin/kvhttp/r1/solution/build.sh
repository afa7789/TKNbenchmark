#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -Xjdk-release=21 -include-runtime -d build/app.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -cp "$dir/build/app.jar" kvhttp.MainKt "$@"
LAUNCHER
chmod +x app
