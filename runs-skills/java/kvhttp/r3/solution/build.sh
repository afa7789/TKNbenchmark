#!/usr/bin/env bash
# Builds the kvhttp server into build/app.jar (plus an AOT cache) and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
javac --release 27 -Xlint:all -Werror -d build/classes $(find src/main/java -name '*.java')
jar --create --file build/app.jar --main-class kvhttp.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec java -Xms128m -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
