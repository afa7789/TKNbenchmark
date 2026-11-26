#!/usr/bin/env bash
# Builds the optimized release binary ./app from src/.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

odin build src \
	-out:app \
	-o:speed \
	-vet \
	-strict-style \
	-disable-assert
