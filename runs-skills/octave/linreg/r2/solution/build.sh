#!/usr/bin/env bash
# Build the compiled number parser into build/ and install the ./app launcher.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
CXXFLAGS="-O2 -DNDEBUG" mkoctfile -o build/parse_numbers.oct src/parse_numbers.cc
rm -f build/*.o

cat > app <<'LAUNCH'
#!/usr/bin/env bash
exec octave-cli -q -f --no-window-system "$(dirname "$0")/linreg.m"
LAUNCH
chmod +x app
