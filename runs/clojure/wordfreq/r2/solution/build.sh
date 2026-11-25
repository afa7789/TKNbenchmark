#!/usr/bin/env bash
# Builds an AOT-compiled, direct-linked uberjar at build/wordfreq.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build classes
mkdir -p build/classes build/stage

clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"build/classes\"] (compile 'wordfreq.core))"

# Unpack the Clojure runtime jars and merge them with our compiled classes.
cp_str="$(clojure -Spath)"
IFS=':' read -ra entries <<< "$cp_str"
for e in "${entries[@]}"; do
  if [[ "$e" == *.jar ]]; then
    (cd build/stage && jar xf "$e")
  fi
done
cp -R build/classes/. build/stage/
rm -rf build/stage/META-INF/*.SF build/stage/META-INF/*.RSA build/stage/META-INF/*.DSA

printf 'Main-Class: wordfreq.core\n' > build/manifest.txt
jar cfm build/wordfreq.jar build/manifest.txt -C build/stage .

cat > app <<'LAUNCH'
#!/usr/bin/env bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xss8m -Xshare:auto \
  -jar "$dir/build/wordfreq.jar" "$@"
LAUNCH
chmod +x app
