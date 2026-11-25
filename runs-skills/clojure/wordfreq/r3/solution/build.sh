#!/usr/bin/env bash
# Builds the AOT-compiled uberjar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto \
  -jar "$DIR/target/wordfreq-standalone.jar" "$@"
LAUNCHER
chmod +x app
