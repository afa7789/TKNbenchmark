#!/usr/bin/env bash
# Builds an AOT-compiled uberjar at target/calc.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target/classes target/uber

# AOT-compile the application (direct linking for speed).
clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"target/classes\"] (compile 'calc.core))"

# Merge the Clojure runtime jars and compiled classes into one jar.
(cd target/uber && for jar in $(cd ../.. && clojure -Spath | tr ':' '\n' | grep '\.jar$'); do
   jar xf "$jar"
 done)
rm -rf target/uber/META-INF
cp -R target/classes/. target/uber/
printf 'Main-Class: calc.core\n' > target/manifest.txt
jar cfm target/calc.jar target/manifest.txt -C target/uber .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -jar "$DIR/target/calc.jar" "$@"
LAUNCHER
chmod +x app
