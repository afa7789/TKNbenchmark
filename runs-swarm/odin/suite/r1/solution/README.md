# suite

Odin implementation of the program specified in [SPEC.md](SPEC.md).

## Build

    ./build.sh        # optimized release binary at ./app
    node check.mjs    # build, then run cases.json against ./app

## Layout

| Path            | Owner    | Contents                                   |
|-----------------|----------|--------------------------------------------|
| `src/main.odin` | shared   | `package main`: dispatches `argv[1]`       |
| `src/wordfreq/` | wordfreq | `package wordfreq`: `./app wordfreq`       |
| `src/lru/`      | lru      | `package lru`: `./app lru`                 |
| `src/calc/`     | calc     | `package calc`: `./app calc`               |
| `src/ioutil/`   | shared   | `package ioutil`: reading standard input   |

Each subcommand package exports one entry point, called by `src/main.odin`:

```odin
run :: proc() -> (exit_code: int)
```

It reads standard input, writes standard output and returns the process exit
status (0 per SPEC.md). Keep everything else in the package private
(`@(private)` or `@(private="file")`) and add as many files to the package
directory as needed. Edit only your own package directory; `src/main.odin`
and `build.sh` are shared.

The build uses `-vet -strict-style`, so unused imports/variables, shadowing
and non-standard formatting are build errors.

Per-subcommand cases: `node check.mjs --cases cases-<name>.json`.
