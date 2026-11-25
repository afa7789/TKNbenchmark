#!/usr/bin/env bash
# Builds an AOT-compiled uberjar, a class-data-sharing archive for fast
# startup, and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

clojure -T:build uber

# Training run: records the loaded classes into the CDS archive.
echo "Warm up the class data sharing archive" \
  | java -XX:+UseSerialGC -XX:ArchiveClassesAtExit=target/wordfreq.jsa \
         -jar target/wordfreq.jar > /dev/null

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:SharedArchiveFile="$dir/target/wordfreq.jsa" -Xshare:auto \
  -jar "$dir/target/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
