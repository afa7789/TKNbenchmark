/*
 * suite: command-line entry point.
 *
 * Dispatches the first argument to the matching subcommand. Each subcommand
 * lives in its own module under src/<name>/ and exposes a single entry point
 * with the same signature as main(); it receives argv shifted so that
 * argv[0] is the subcommand name.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "calc/calc.h"
#include "lru/lru.h"
#include "wordfreq/wordfreq.h"

typedef int (*command_fn)(int argc, char **argv);

struct command {
    const char *name;
    command_fn run;
};

static const struct command commands[] = {
    { "wordfreq", wordfreq_main },
    { "lru",      lru_main },
    { "calc",     calc_main },
};

enum { NUM_COMMANDS = sizeof commands / sizeof commands[0] };

static void usage(FILE *out, const char *prog)
{
    fprintf(out, "usage: %s <command>\n\ncommands:\n", prog);
    for (size_t i = 0; i < NUM_COMMANDS; i++)
        fprintf(out, "  %s\n", commands[i].name);
}

int main(int argc, char **argv)
{
    const char *prog = (argc > 0 && argv[0] != NULL) ? argv[0] : "app";

    if (argc < 2) {
        usage(stderr, prog);
        return EXIT_FAILURE;
    }

    for (size_t i = 0; i < NUM_COMMANDS; i++) {
        if (strcmp(argv[1], commands[i].name) == 0)
            return commands[i].run(argc - 1, argv + 1);
    }

    fprintf(stderr, "%s: unknown command '%s'\n", prog, argv[1]);
    usage(stderr, prog);
    return EXIT_FAILURE;
}
