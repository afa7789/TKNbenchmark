#!/usr/bin/env bash
# Builds build/app.jar, trains an AOT cache for fast startup, and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -O -Xlint:all -Werror -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class lru.Main -C build/classes .

# Train the AOT cache on a representative workload; startup still works without it.
{
  echo 100
  for i in $(seq 1 3000); do
    echo "SET k$((i % 250)) v$i"; echo "GET k$((i % 170))"; echo "DEL k$((i % 333))"
  done
  echo SIZE
} > build/train.txt
if ! java -XX:AOTCacheOutput=build/app.aot -jar build/app.jar < build/train.txt > /dev/null 2>&1; then
  rm -f build/app.aot
fi

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
aot=()
[[ -f "$dir/build/app.aot" ]] && aot=(-XX:AOTCache="$dir/build/app.aot")
exec java -XX:+UseSerialGC -Xms256m "${aot[@]}" -jar "$dir/build/app.jar" "$@"
LAUNCHER
chmod +x app
