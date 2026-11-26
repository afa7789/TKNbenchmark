#ifndef SUITE_COMMANDS_H
#define SUITE_COMMANDS_H

#include <stdio.h>

/* Each subcommand reads `in`, writes `out` and returns the exit status. */
int cmd_wordfreq(FILE *in, FILE *out);
int cmd_lru(FILE *in, FILE *out);
int cmd_calc(FILE *in, FILE *out);

#endif
