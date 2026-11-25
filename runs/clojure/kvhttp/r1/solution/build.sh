#!/usr/bin/env bash
# Builds an AOT-compiled uberjar and a ./app launcher for it.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss1m -jar "$DIR/target/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
