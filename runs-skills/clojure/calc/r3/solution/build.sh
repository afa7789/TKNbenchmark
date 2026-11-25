#!/usr/bin/env bash
# Builds the release uberjar and a ./app launcher that runs it.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto -jar "$DIR/target/calc-standalone.jar" "$@"
LAUNCHER
chmod +x app
