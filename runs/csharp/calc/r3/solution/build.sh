#!/usr/bin/env bash
# Builds an optimized release binary of the calculator and places it at ./app.
set -euo pipefail

cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

out_dir="$PWD/.build"
rm -rf "$out_dir"

dotnet publish src/Calc.csproj \
  --configuration Release \
  --output "$out_dir" \
  -p:UseAppHost=true \
  -p:DebugType=none \
  --nologo \
  --verbosity quiet

# The framework-dependent apphost needs to find the .NET runtime; Homebrew and
# other non-default installs are not on its search path, so record the root of
# the SDK used for this build and launch through it.
sdk_base="$(dotnet --info | sed -n 's/^ *Base Path: *//p' | head -n 1)"
dotnet_root="$(cd "$sdk_base/../.." && pwd)"

cat > app <<LAUNCHER
#!/usr/bin/env bash
export DOTNET_ROOT="\${DOTNET_ROOT:-$dotnet_root}"
exec "\$(dirname "\$0")/.build/app" "\$@"
LAUNCHER
chmod +x app
