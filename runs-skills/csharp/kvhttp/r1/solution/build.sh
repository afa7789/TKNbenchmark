#!/usr/bin/env bash
# Builds a native (AOT) release binary of the kvhttp server and places it at ./app.
set -euo pipefail
cd "$(dirname "$0")"

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# Homebrew's .NET SDK links against Homebrew-provided native libraries.
if command -v brew >/dev/null 2>&1; then
    lib_path=""
    for formula in openssl@3 brotli zstd; do
        if prefix=$(brew --prefix "$formula" 2>/dev/null) && [ -d "$prefix/lib" ]; then
            lib_path="${lib_path:+$lib_path:}$prefix/lib"
        fi
    done
    export LIBRARY_PATH="${lib_path}${LIBRARY_PATH:+:$LIBRARY_PATH}"
fi

rid="$(dotnet --info | awk -F': *' '/^ *RID:/ {print $2; exit}')"
rm -rf publish
dotnet publish src/KvHttp/KvHttp.csproj -c Release -r "$rid" -o publish
cp publish/kvhttp app
chmod +x app
