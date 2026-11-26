#include "commands.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const struct {
    const char *name;
    int (*run)(void);
} commands[] = {
    { "wordfreq", cmd_wordfreq },
    { "lru", cmd_lru },
    { "calc", cmd_calc },
};

int main(int argc, char **argv)
{
    if (argc >= 2) {
        for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
            if (strcmp(argv[1], commands[i].name) == 0)
                return commands[i].run();
        }
    }
    fprintf(stderr, "usage: %s wordfreq|lru|calc < input\n", argc ? argv[0] : "app");
    return EXIT_FAILURE;
}
