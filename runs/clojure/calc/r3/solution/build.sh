#!/usr/bin/env bash
# Builds an AOT-compiled uberjar (target/app.jar) and the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target/classes target/uber

# AOT-compile with direct linking for faster startup and calls.
clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"target/classes\"] (compile 'calc.main))"

# Assemble the uberjar: Clojure runtime jars plus our compiled classes.
IFS=: read -r -a cp <<< "$(clojure -Spath)"
for entry in "${cp[@]}"; do
  if [[ "$entry" == *.jar ]]; then
    (cd target/uber && jar xf "$entry")
  fi
done
rm -rf target/uber/META-INF
cp -R target/classes/. target/uber/
jar --create --file target/app.jar --main-class calc.main -C target/uber .

JAVA_OPTS=(-XX:+UseSerialGC -Xss8m)

# Class-data-sharing archive to cut JVM startup time.
echo "1+1" | java "${JAVA_OPTS[@]}" -XX:ArchiveClassesAtExit=target/app.jsa \
  -jar target/app.jar > /dev/null 2>&1 || true

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cds=()
[[ -f "$dir/target/app.jsa" ]] && cds=(-XX:SharedArchiveFile="$dir/target/app.jsa" -Xlog:cds=off -Xlog:cds+dynamic=off)
exec java -XX:+UseSerialGC -Xss8m "${cds[@]}" -jar "$dir/target/app.jar" "$@"
LAUNCHER
chmod +x app
