#!/usr/bin/env bash
# Builds the release uberjar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:SharedArchiveFile="$DIR/target/app.jsa" -Xshare:auto \
  -Xlog:cds=off -Xlog:aot=off -jar "$DIR/target/lru-standalone.jar" "$@"
LAUNCHER
chmod +x app

# Pre-build a class-data-sharing archive to cut JVM startup time.
printf '1\nSIZE\n' | java -XX:ArchiveClassesAtExit=target/app.jsa -Xlog:cds=off -Xlog:aot=off \
  -jar target/lru-standalone.jar >/dev/null 2>&1 || true
