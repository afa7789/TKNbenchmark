#!/usr/bin/env bash
# Builds a self-contained, AOT-compiled (direct-linked) uberjar and an ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target/classes target/uber

clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"target/classes\"] (compile 'lru.main))"

# Merge the Clojure runtime jars with our compiled classes.
IFS=':' read -r -a cp <<< "$(clojure -Spath)"
(
  cd target/uber
  for entry in "${cp[@]}"; do
    case "$entry" in
      *.jar) jar xf "$entry" ;;
    esac
  done
  rm -rf META-INF
)
cp -R target/classes/. target/uber/
jar --create --file target/lru.jar --main-class lru.main -C target/uber .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xss16m -jar "$DIR/target/lru.jar" "$@"
LAUNCHER
chmod +x app
