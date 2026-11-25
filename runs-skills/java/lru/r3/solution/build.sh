#!/usr/bin/env bash
# Builds build/app.jar, an AOT cache for fast startup, and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -encoding UTF-8 -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class lru.Main -C build/classes .

JAVA_OPTS=(-XX:+UseSerialGC -Xms256m)

# Train an AOT cache on a representative workload; skip it if unsupported.
training=$(mktemp)
trap 'rm -f "$training"' EXIT
{
  echo 1000
  for i in $(seq 1 20000); do
    k=$((i % 1500))
    echo "SET k$k v$i"; echo "GET k$((i % 1700))"
    if (( i % 7 == 0 )); then echo "DEL k$((i % 1300))"; fi
    if (( i % 31 == 0 )); then echo "SIZE"; fi
  done
} > "$training"
if java "${JAVA_OPTS[@]}" -XX:AOTCacheOutput=build/app.aot -jar build/app.jar < "$training" > /dev/null 2>&1; then
  AOT_OPT='-XX:AOTCache="$DIR/build/app.aot"'
else
  rm -f build/app.aot
  AOT_OPT=''
fi

cat > app <<LAUNCHER
#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec java ${JAVA_OPTS[*]} ${AOT_OPT} -jar "\$DIR/build/app.jar" "\$@"
LAUNCHER
chmod +x app
