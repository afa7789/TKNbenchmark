#!/usr/bin/env bash
# Builds the server jar and a launcher at ./app. No third-party dependencies
# beyond the Kotlin compiler and a JDK (21+, for virtual threads).
set -euo pipefail
cd "$(dirname "$0")"

command -v kotlinc >/dev/null || { echo "build.sh: kotlinc not found on PATH" >&2; exit 1; }
command -v java >/dev/null || { echo "build.sh: java not found on PATH" >&2; exit 1; }

rm -rf build
mkdir -p build
kotlinc src/main/kotlin -jvm-target 21 -include-runtime -d build/app.jar

cat > app <<'EOF'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -XX:-UsePerfData -jar "$dir/build/app.jar" "$@"
EOF
chmod +x app
