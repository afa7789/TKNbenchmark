#!/usr/bin/env bash
# Builds the kvhttp server into build/kvhttp.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/kvhttp.jar --main-class kvhttp.KvServer -C build/classes .

# Class-data sharing archive for faster startup (best effort).
java -XX:ArchiveClassesAtExit=build/kvhttp.jsa -jar build/kvhttp.jar 0 >/dev/null 2>&1 &
pid=$!
sleep 1
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
cds=()
[[ -f "$dir/build/kvhttp.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/build/kvhttp.jsa" -Xshare:auto)
exec java "${cds[@]}" -XX:+UseSerialGC -Xss512k -jar "$dir/build/kvhttp.jar" "$@"
LAUNCHER
chmod +x app
