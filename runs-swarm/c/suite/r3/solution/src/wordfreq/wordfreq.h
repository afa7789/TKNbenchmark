/* wordfreq: word frequencies. See the "wordfreq" section of SPEC.md. */
#ifndef WORDFREQ_H
#define WORDFREQ_H

/*
 * Runs the subcommand. argv[0] is "wordfreq"; argv[1..argc-1] are any further
 * arguments. Reads standard input, writes standard output, and returns the
 * process exit status.
 */
int wordfreq_main(int argc, char **argv);

#endif
