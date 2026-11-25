#!/usr/bin/env bash
# Builds an AOT-compiled, direct-linked uberjar at build/lru.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build classes
mkdir -p classes build/jar

clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(compile 'lru.main)"

# Unpack the runtime dependencies (clojure, spec, core.specs) into the jar root.
cp=$(clojure -Spath)
IFS=':' read -ra entries <<< "$cp"
for e in "${entries[@]}"; do
  if [[ "$e" == *.jar ]]; then
    (cd build/jar && unzip -qo "$e" -x 'META-INF/*')
  fi
done
cp -R classes/. build/jar/

printf 'Main-Class: lru.main\n' > build/manifest.txt
jar --create --file build/lru.jar --manifest build/manifest.txt -C build/jar .
rm -rf build/jar build/manifest.txt classes

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -Xshare:auto -jar "$dir/build/lru.jar" "$@"
LAUNCHER
chmod +x app
