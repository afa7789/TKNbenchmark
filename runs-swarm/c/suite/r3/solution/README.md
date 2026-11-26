# suite

`./app <command>` — see SPEC.md.

Build: `./build.sh` (optimized release binary at `./app`). `make debug` builds
`./app-debug` with ASan/UBSan. Test: `node check.mjs`.

## Layout

| Path            | Owner    | Contents                              |
|-----------------|----------|---------------------------------------|
| `src/main.c`    | lead     | dispatches `argv[1]` to a subcommand  |
| `src/wordfreq/` | wordfreq | `wordfreq_main` in `wordfreq.h`       |
| `src/lru/`      | lru      | `lru_main` in `lru.h`                 |
| `src/calc/`     | calc     | `calc_main` in `calc.h`               |

Each subcommand lives entirely in its own directory; replace the stub in
`<name>.c` and add any further `.c`/`.h` files there. The Makefile compiles
every `.c` under `src/`, so it needs no edits. Keep non-static symbols
prefixed with the subcommand name (`lru_…`) to avoid link clashes, and include
headers by their path from `src/` (e.g. `#include "lru/table.h"`).
