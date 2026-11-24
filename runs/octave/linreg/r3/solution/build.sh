#!/usr/bin/env bash
# Octave is interpreted; "building" just validates the toolchain and makes the launcher executable.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v octave-cli >/dev/null || { echo "octave-cli not found" >&2; exit 1; }
chmod +x app
