#!/usr/bin/env bash
# Builds the calc release jar and an ./app launcher script.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
kotlinc src/*.kt -include-runtime -nowarn -d build/app.jar

# Class-data-sharing archive to cut JVM startup time (best effort).
rm -f build/app.jsa
echo "1+1" | java -XX:ArchiveClassesAtExit=build/app.jsa -jar build/app.jar >/dev/null 2>&1 || rm -f build/app.jsa

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDS=()
[[ -f "$DIR/build/app.jsa" ]] && CDS=(-XX:SharedArchiveFile="$DIR/build/app.jsa" -Xshare:auto)
exec java "${CDS[@]}" -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
