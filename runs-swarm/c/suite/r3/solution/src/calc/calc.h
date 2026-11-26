/* calc: 64-bit integer expression evaluator. See the "calc" section of SPEC.md. */
#ifndef CALC_H
#define CALC_H

/*
 * Runs the subcommand. argv[0] is "calc"; argv[1..argc-1] are any further
 * arguments. Reads standard input, writes standard output, and returns the
 * process exit status.
 */
int calc_main(int argc, char **argv);

#endif
