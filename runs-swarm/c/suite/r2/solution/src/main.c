/*
 * Entry point: dispatches the first argument to a subcommand.
 *
 * Each subcommand receives argc/argv shifted so that argv[0] is the
 * subcommand name, and its return value becomes the process exit status.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "calc/calc.h"
#include "lru/lru.h"
#include "wordfreq/wordfreq.h"

struct command {
    const char *name;
    int (*run)(int argc, char **argv);
};

static const struct command commands[] = {
    { "wordfreq", wordfreq_main },
    { "lru",      lru_main      },
    { "calc",     calc_main     },
};

static void usage(FILE *out, const char *prog)
{
    fprintf(out, "usage: %s <command>\n\ncommands:\n", prog);
    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++)
        fprintf(out, "  %s\n", commands[i].name);
}

int main(int argc, char **argv)
{
    const char *prog = argc > 0 ? argv[0] : "app";

    if (argc < 2) {
        usage(stderr, prog);
        return EXIT_FAILURE;
    }

    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
        if (strcmp(argv[1], commands[i].name) == 0)
            return commands[i].run(argc - 1, argv + 1);
    }

    fprintf(stderr, "%s: unknown command '%s'\n", prog, argv[1]);
    usage(stderr, prog);
    return EXIT_FAILURE;
}
