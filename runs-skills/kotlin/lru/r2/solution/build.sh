#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/*.kt -include-runtime -jvm-target 21 -d build/app.jar
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss8m -jar "$(dirname "$0")/build/app.jar" "$@"
SH
chmod +x app
