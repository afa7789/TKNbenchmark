#!/usr/bin/env bash
# Builds the kvhttp server into build/app.jar and writes the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build
mkdir -p build/classes
find src/main/java -name '*.java' -print0 | xargs -0 javac --release 27 -Xlint:all -Werror -d build/classes
jar --create --file build/app.jar --main-class kvhttp.Main -C build/classes .

cat > app <<'LAUNCHER'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java -XX:+UseSerialGC -Xss512k -Xms64m -jar "$DIR/build/app.jar" "$@"
LAUNCHER
chmod +x app
