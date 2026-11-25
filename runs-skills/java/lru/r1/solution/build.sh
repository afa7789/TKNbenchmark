#!/usr/bin/env bash
# Builds build/app.jar, an AOT cache for fast startup, and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -O -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class lru.Main -C build/classes .

# Train an AOT cache on a representative workload (best effort: the launcher works without it).
{
  echo 100
  for i in $(seq 1 2000); do
    echo "SET k$((i % 300)) v$i"; echo "GET k$((i % 170))"; echo "DEL k$((i % 410))"; echo SIZE
  done
} > build/train.txt
java -Xms256m -XX:+UseSerialGC -XX:AOTCacheOutput=build/app.aot -jar build/app.jar < build/train.txt > /dev/null 2>&1 \
  || rm -f build/app.aot

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aot=()
[[ -f "$dir/build/app.aot" ]] && aot=(-XX:AOTCache="$dir/build/app.aot")
exec java "${aot[@]}" -Xms256m -XX:+UseSerialGC -jar "$dir/build/app.jar" "$@"
LAUNCHER
chmod +x app
