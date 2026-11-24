#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/app.jar
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -jar "$(dirname "$0")/build/app.jar" "$@"
SH
chmod +x app
