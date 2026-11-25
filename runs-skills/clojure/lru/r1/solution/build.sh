#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
clojure -T:build uber
cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -Xshare:auto -jar "$DIR/target/lru-standalone.jar" "$@"
LAUNCHER
chmod +x app
