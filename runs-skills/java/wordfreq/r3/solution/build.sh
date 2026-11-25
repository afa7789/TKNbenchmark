#!/usr/bin/env bash
# Builds build/wordfreq.jar (plus an AOT cache for fast startup) and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/wordfreq.jar --main-class wordfreq.Main -C build/classes .

# Train an AOT cache on a representative input; the launcher works without it too.
printf 'The cat and the hat. Hello, hello! HELLO? don'"'"'t stop_me 4now\n%.0s' {1..2000} \
  | java -XX:+UseSerialGC -XX:AOTCacheOutput=build/app.aot -jar build/wordfreq.jar > /dev/null 2>&1 \
  || rm -f build/app.aot

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
opts=(-XX:+UseSerialGC -Xms64m)
if [[ -f "$dir/build/app.aot" ]]; then
  opts+=(-XX:AOTCache="$dir/build/app.aot")
fi
exec java "${opts[@]}" -jar "$dir/build/wordfreq.jar"
LAUNCHER
chmod +x app
