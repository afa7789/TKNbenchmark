#!/usr/bin/env bash
# Builds an optimized, natively compiled release binary at ./app.
set -euo pipefail

cd "$(dirname "$0")"

dotnet publish src/WordFreq.csproj \
    --configuration Release \
    --output publish \
    --nologo

cp publish/app ./app
chmod +x ./app
