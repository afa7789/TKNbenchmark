#!/usr/bin/env bash
# Builds the calc release jar, an AOT cache for fast startup, and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build app
mkdir -p build/classes
javac --release 27 -d build/classes $(find src -name '*.java')
jar --create --file build/calc.jar --main-class calc.Main -C build/classes .

# Train an AOT cache so the JVM starts quickly; skip silently if unsupported.
printf '1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n\n  -(4 %% 3) * 5\n' \
  | java -XX:+UseSerialGC -XX:AOTCacheOutput=build/calc.aot -jar build/calc.jar >/dev/null 2>&1 || rm -f build/calc.aot

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aot=()
[[ -f "$dir/build/calc.aot" ]] && aot=(-XX:AOTCache="$dir/build/calc.aot")
exec java "${aot[@]}" -XX:+UseSerialGC -jar "$dir/build/calc.jar" "$@"
LAUNCHER
chmod +x app
