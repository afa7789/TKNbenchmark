#!/usr/bin/env bash
# Builds a self-contained AOT-compiled jar at target/wordfreq.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target/classes

# AOT-compile with direct linking for faster startup and calls.
clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"target/classes\"] (compile 'wordfreq.core))"

# Bundle the Clojure runtime jars into the classes directory.
cp_jars=$(clojure -Spath | tr ':' '\n' | grep '\.jar$')
(cd target/classes && for j in $cp_jars; do jar xf "$j"; done && rm -rf META-INF)

printf 'Main-Class: wordfreq.core\n' > target/manifest.txt
jar cfm target/wordfreq.jar target/manifest.txt -C target/classes .

cat > app <<'LAUNCH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -jar "$here/target/wordfreq.jar" "$@"
LAUNCH
chmod +x app
