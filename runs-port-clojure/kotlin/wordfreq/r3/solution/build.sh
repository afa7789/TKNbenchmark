#!/usr/bin/env bash
# Builds a self-contained jar at target/wordfreq.jar and a launcher at ./app.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf target
mkdir -p target

kotlinc src -include-runtime -jvm-target 17 -d target/wordfreq.jar 2>&1 | grep -v '^warning:' || true
[[ -f target/wordfreq.jar ]] || { echo "build failed" >&2; exit 1; }

cat > app <<'LAUNCH'
#!/usr/bin/env bash
here="$(cd "$(dirname "$0")" && pwd)"
exec java -XX:+UseSerialGC -Xshare:auto -cp "$here/target/wordfreq.jar" wordfreq.MainKt "$@"
LAUNCH
chmod +x app
