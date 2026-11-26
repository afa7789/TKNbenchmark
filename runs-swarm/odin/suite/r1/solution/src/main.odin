// Entry point of ./app: dispatches the first argument to a subcommand.
//
// Each subcommand lives in its own package under src/ and exposes
//
//     run :: proc() -> (exit_code: int)
//
// which reads standard input, writes standard output and returns the
// process exit status.
package main

import "core:fmt"
import "core:os"

import "calc"
import "lru"
import "wordfreq"

Subcommand :: struct {
	name: string,
	run:  proc() -> (exit_code: int),
}

SUBCOMMANDS :: [?]Subcommand {
	{"wordfreq", wordfreq.run},
	{"lru",      lru.run},
	{"calc",     calc.run},
}

EXIT_USAGE :: 2

main :: proc() {
	os.exit(dispatch(os.args))
}

dispatch :: proc(args: []string) -> (exit_code: int) {
	if len(args) < 2 {
		usage(args)
		return EXIT_USAGE
	}

	name := args[1]
	for cmd in SUBCOMMANDS {
		if cmd.name == name {
			return cmd.run()
		}
	}

	fmt.eprintfln("unknown subcommand: %q", name)
	usage(args)
	return EXIT_USAGE
}

usage :: proc(args: []string) {
	program := len(args) > 0 ? args[0] : "app"
	fmt.eprintf("usage: %s <subcommand>\n\nsubcommands:\n", program)
	for cmd in SUBCOMMANDS {
		fmt.eprintfln("  %s", cmd.name)
	}
}
