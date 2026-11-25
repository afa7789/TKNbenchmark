#!/usr/bin/env bash
# Builds the calc release: compiles sources into app.jar, trains an AOT cache
# for fast startup, and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build app app.jar app.aot
mkdir -p build/classes
javac --release 27 -O -g:none -d build/classes $(find src/main/java -name '*.java')
jar --create --file app.jar --main-class calc.Main -C build/classes .

JVM_OPTS=(-XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xlog:disable -Xlog:all=off)
printf '1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n  \n7 %% -3\n1/0\nabc\n' \
    | java "${JVM_OPTS[@]}" -XX:AOTCacheOutput=app.aot -jar app.jar > /dev/null || rm -f app.aot

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opts=(-XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xlog:disable -Xlog:all=off)
[[ -f "$dir/app.aot" ]] && opts+=(-XX:AOTCache="$dir/app.aot")
exec java "${opts[@]}" -jar "$dir/app.jar"
LAUNCHER
chmod +x app
