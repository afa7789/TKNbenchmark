#!/usr/bin/env bash
# Builds a self-contained jar (Kotlin runtime included) and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target app
mkdir -p target

kotlinc src -include-runtime -jvm-target 21 -d target/lru.jar 2>&1 | grep -v '^warning:' || true
test -f target/lru.jar

cat > app <<'LAUNCH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xms512m \
  -cp "$DIR/target/lru.jar" lru.MainKt "$@"
LAUNCH
chmod +x app
