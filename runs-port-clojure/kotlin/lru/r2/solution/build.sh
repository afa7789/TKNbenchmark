#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target

kotlinc src/main/kotlin -include-runtime -jvm-target 21 -d target/lru.jar

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -jar "$DIR/target/lru.jar" "$@"
LAUNCHER
chmod +x app
