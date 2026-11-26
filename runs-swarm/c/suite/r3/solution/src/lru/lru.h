/* lru: LRU cache simulator. See the "lru" section of SPEC.md. */
#ifndef LRU_H
#define LRU_H

/*
 * Runs the subcommand. argv[0] is "lru"; argv[1..argc-1] are any further
 * arguments. Reads standard input, writes standard output, and returns the
 * process exit status.
 */
int lru_main(int argc, char **argv);

#endif
