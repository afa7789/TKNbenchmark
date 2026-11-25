#!/usr/bin/env bash
# Builds an AOT-compiled, direct-linked uberjar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target app
mkdir -p target/classes target/uber

clojure -J-Dclojure.compiler.direct-linking=true \
        -J-Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
        -M -e "(binding [*compile-path* \"target/classes\"] (compile 'calc.main))"

# Merge Clojure runtime jars with our classes into a single jar.
IFS=: read -ra CP <<< "$(clojure -Spath)"
(
  cd target/uber
  for entry in "${CP[@]}"; do
    case "$entry" in
      *.jar) jar xf "$entry" ;;
    esac
  done
  rm -rf META-INF/*.SF META-INF/*.RSA META-INF/*.DSA
)
cp -R target/classes/. target/uber/
jar --create --file target/calc.jar --main-class calc.main -C target/uber .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto \
  -jar "$DIR/target/calc.jar" "$@"
LAUNCHER
chmod +x app
