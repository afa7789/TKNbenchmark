#!/usr/bin/env bash
# Builds the calc evaluator into build/calc.jar (plus an AOT cache) and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -Xlint:all -Werror -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/calc.jar --main-class calc.Main -C build/classes .

# Train an AOT cache to cut JVM startup time; the launcher works without it too.
printf '1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n\n' \
    | java -XX:+UseSerialGC -XX:AOTCacheOutput=build/calc.aot -jar build/calc.jar >/dev/null 2>&1 || rm -f build/calc.aot

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
aot=()
[[ -f "$dir/build/calc.aot" ]] && aot=(-XX:AOTCache="$dir/build/calc.aot" -Xlog:aot=off -Xlog:cds=off)
exec java -XX:+UseSerialGC "${aot[@]}" -jar "$dir/build/calc.jar" "$@"
LAUNCHER
chmod +x app
