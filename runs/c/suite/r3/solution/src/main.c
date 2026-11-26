#include <stdio.h>
#include <string.h>

#include "commands.h"

#define OUTPUT_BUFFER_SIZE ((size_t)1 << 16)

static const struct {
    const char *name;
    int (*run)(FILE *in, FILE *out);
} commands[] = {
    { "wordfreq", cmd_wordfreq },
    { "lru", cmd_lru },
    { "calc", cmd_calc },
};

static int usage(void)
{
    fputs("usage: app <wordfreq|lru|calc>  (reads stdin, writes stdout)\n", stderr);
    return 2;
}

int main(int argc, char **argv)
{
    if (argc != 2)
        return usage();

    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) {
        if (strcmp(argv[1], commands[i].name) == 0) {
            static char outbuf[OUTPUT_BUFFER_SIZE];
            setvbuf(stdout, outbuf, _IOFBF, sizeof outbuf);

            int status = commands[i].run(stdin, stdout);
            if (fflush(stdout) != 0 || ferror(stdout)) {
                perror("app: write error");
                return 1;
            }
            return status;
        }
    }
    return usage();
}
