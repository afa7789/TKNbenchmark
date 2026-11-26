# suite

Implementation of the program described in `SPEC.md`.

## Build

    ./build.sh        # optimized release binary at ./app
    make OPTFLAGS="-O0 -g -fsanitize=address,undefined" LDFLAGS="-fsanitize=address,undefined"
                      # debug build with sanitizers (run `make clean` when switching)

## Layout

    src/main.c              dispatcher: ./app <command> -> <command>_main()
    src/wordfreq/           `app wordfreq`  (branch wordfreq)
    src/lru/                `app lru`       (branch lru)
    src/calc/               `app calc`      (branch calc)

Each subcommand module exposes exactly one entry point, declared in
`src/<name>/<name>.h`:

    int <name>_main(int argc, char **argv);   /* argv[0] == "<name>" */

It returns the process exit status. Engineers edit only files inside their own
`src/<name>/` directory; any additional `.c`/`.h` files placed there are picked
up by the Makefile automatically. Internal helpers should be `static` or
prefixed with `<name>_` to avoid link-time collisions between modules.

## Testing

    node check.mjs                          # all cases
    node check.mjs --cases cases-calc.json  # one subcommand
