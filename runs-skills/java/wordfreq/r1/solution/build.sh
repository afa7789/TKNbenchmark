#!/usr/bin/env bash
# Builds build/app.jar, an AOT cache for fast startup, and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -O -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class wordfreq.Main -C build/classes .

JAVA_OPTS=(-XX:+UseSerialGC -Xss512k -XX:-UsePerfData)

# Train an AOT cache on a small sample input; startup works without it if this fails.
printf 'The cat and the hat. Hello, hello! HELLO? world\n%.0s' {1..2000} \
  | java "${JAVA_OPTS[@]}" -XX:AOTCacheOutput=build/app.aot -jar build/app.jar >/dev/null 2>&1 \
  || rm -f build/app.aot

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aot=()
[[ -f "$dir/build/app.aot" ]] && aot=(-XX:AOTCache="$dir/build/app.aot")
exec java -XX:+UseSerialGC -Xss512k -XX:-UsePerfData -Xms64m "${aot[@]}" -jar "$dir/build/app.jar" "$@"
LAUNCHER
chmod +x app
