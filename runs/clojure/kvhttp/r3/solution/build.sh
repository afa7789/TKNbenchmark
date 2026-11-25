#!/usr/bin/env bash
# Builds an AOT-compiled uberjar and a launcher script at ./app.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss512k -Xshare:auto \
  -jar "$DIR/target/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
