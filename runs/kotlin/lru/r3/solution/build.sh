#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/Main.kt -include-runtime -d build/app.jar -nowarn
cat > app <<'SH'
#!/usr/bin/env bash
exec java -XX:+UseSerialGC -Xshare:auto -XX:TieredStopAtLevel=1 -jar "$(dirname "$0")/build/app.jar" "$@"
SH
chmod +x app
