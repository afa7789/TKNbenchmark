#ifndef SUITE_COMMANDS_H
#define SUITE_COMMANDS_H

/* Each subcommand reads stdin, writes stdout, and returns an exit status. */
int cmd_wordfreq(void);
int cmd_lru(void);
int cmd_calc(void);

#endif
