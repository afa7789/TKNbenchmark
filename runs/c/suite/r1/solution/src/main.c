#include "commands.h"
#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const struct {
    const char *name;
    int (*run)(void);
} commands[] = {
    {"wordfreq", cmd_wordfreq},
    {"lru", cmd_lru},
    {"calc", cmd_calc},
};

static void usage(void)
{
    fputs("usage: app <wordfreq|lru|calc>  (reads stdin, writes stdout)\n", stderr);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        usage();
        return 2;
    }
    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
        if (strcmp(argv[1], commands[i].name) == 0) {
            setup_stdout();
            int status = commands[i].run();
            if (fflush(stdout) != 0 || ferror(stdout))
                die("write error on standard output");
            return status;
        }
    }
    usage();
    return 2;
}
