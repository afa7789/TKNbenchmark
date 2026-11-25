#!/usr/bin/env bash
# Builds a self-contained AOT-compiled uberjar and a ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target app
mkdir -p target/classes target/uber

cp_path=$(clojure -Spath)

java -cp "target/classes:${cp_path}" \
  -Dclojure.compile.path=target/classes \
  -Dclojure.compiler.direct-linking=true \
  -Dclojure.compiler.elide-meta='[:doc :file :line :added]' \
  clojure.main -e "(compile 'wordfreq.core)"

# Unpack dependency jars, then overlay our compiled classes.
IFS=':' read -ra entries <<< "${cp_path}"
for entry in "${entries[@]}"; do
  if [[ "${entry}" == *.jar ]]; then
    (cd target/uber && jar xf "${entry}")
  fi
done
rm -rf target/uber/META-INF
cp -R target/classes/. target/uber/

jar --create --file target/wordfreq.jar --main-class wordfreq.core -C target/uber .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xss16m -XX:TieredStopAtLevel=4 -Xshare:auto \
  -jar "${dir}/target/wordfreq.jar" "$@"
LAUNCHER
chmod +x app
