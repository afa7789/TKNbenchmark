#!/usr/bin/env bash
# Builds the calc application into build/calc.jar and installs the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 21 -d build/classes $(find src -name '*.java')
jar --create --file build/calc.jar --main-class calc.Main -C build/classes .

# Class-data-sharing archive to cut JVM startup time (best effort).
echo "1+1" | java -XX:ArchiveClassesAtExit=build/calc.jsa -jar build/calc.jar >/dev/null 2>&1 || rm -f build/calc.jsa

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opts=(-XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xshare:auto)
if [[ -f "$dir/build/calc.jsa" ]]; then
  opts+=("-XX:SharedArchiveFile=$dir/build/calc.jsa")
fi
exec java "${opts[@]}" -jar "$dir/build/calc.jar"
LAUNCHER
chmod +x app
