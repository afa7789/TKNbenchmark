#!/usr/bin/env bash
# Builds a self-contained, AOT-compiled uberjar and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target app
mkdir -p target/classes target/uber

# AOT-compile with direct linking for faster startup and calls.
clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"target/classes\"] (compile 'lru.main))"

# Merge Clojure runtime jars and compiled classes into one jar.
cp_line="$(clojure -Spath)"
IFS=':' read -ra entries <<< "$cp_line"
for e in "${entries[@]}"; do
  if [[ "$e" == *.jar ]]; then
    (cd target/uber && jar xf "$e")
  fi
done
cp -R target/classes/. target/uber/
rm -rf target/uber/META-INF/*.SF target/uber/META-INF/*.RSA target/uber/META-INF/*.DSA
jar --create --file target/lru.jar --main-class lru.main -C target/uber .

cat > app <<'LAUNCH'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xms512m \
  -jar "$DIR/target/lru.jar" "$@"
LAUNCH
chmod +x app
