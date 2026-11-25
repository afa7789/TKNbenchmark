#!/usr/bin/env bash
# Builds the release uberjar and an ./app launcher that runs it.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=4 -Xss8m -Xshare:auto \
  -XX:SharedArchiveFile="$dir/target/app.jsa" -XX:+AutoCreateSharedArchive \
  -jar "$dir/target/wordfreq-standalone.jar" "$@"
LAUNCHER
chmod +x app

# Warm up the class-data sharing archive so the first real run starts fast.
echo "warm up" | ./app > /dev/null
