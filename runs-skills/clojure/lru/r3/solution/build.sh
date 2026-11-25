#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
clojure -T:build uber
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/target/lru-standalone.jar" "$@"
SH
chmod +x app
