#!/usr/bin/env bash
# Builds target/app.jar (Kotlin runtime included) and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target

kotlinc src -include-runtime -d target/app.jar 2>&1 | grep -v '^warning:' || true
[[ -f target/app.jar ]] || { echo "compilation failed" >&2; exit 1; }

JAVA_OPTS=(-XX:+UseSerialGC)

# Class-data-sharing archive to cut JVM startup time.
echo "1+1" | java "${JAVA_OPTS[@]}" -XX:ArchiveClassesAtExit=target/app.jsa \
  -jar target/app.jar > /dev/null 2>&1 || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cds=()
[[ -f "$dir/target/app.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/target/app.jsa" -Xlog:cds=off -Xlog:cds+dynamic=off)
exec java -XX:+UseSerialGC "${cds[@]}" -jar "$dir/target/app.jar" "$@"
LAUNCHER
chmod +x app
