#!/usr/bin/env bash
# Builds an AOT-compiled uberjar at target/calc.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target/classes target/uber

clojure -M -e "(binding [*compile-path* \"target/classes\"
                         *compiler-options* {:direct-linking true
                                             :elide-meta [:doc :file :line :added]}]
                 (compile 'calc.core))"

# Assemble the uberjar: Clojure runtime + our compiled classes.
(cd target/uber && for j in $(clojure -Spath | tr ':' '\n' | grep '\.jar$'); do jar xf "$j"; done)
rm -rf target/uber/META-INF
cp -R target/classes/. target/uber/
jar --create --file target/calc.jar --main-class calc.core -C target/uber .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -Xss512m -XX:+UseSerialGC -Xshare:auto -jar "$DIR/target/calc.jar" "$@"
LAUNCHER
chmod +x app
