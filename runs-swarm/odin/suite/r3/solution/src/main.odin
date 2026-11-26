// Command suite dispatches its first argument to one of three independent subcommands.
// Each subcommand lives in its own package under src/ and exposes a single `run` entry point.
package main

import "core:fmt"
import "core:os"

import "calc"
import "lru"
import "wordfreq"

Command :: struct {
	name: string,
	run:  proc(),
}

COMMANDS :: [?]Command {
	{"wordfreq", wordfreq.run},
	{"lru", lru.run},
	{"calc", calc.run},
}

main :: proc() {
	if len(os.args) < 2 {
		usage()
	}

	name := os.args[1]
	for command in COMMANDS {
		if command.name == name {
			command.run()
			return
		}
	}

	fmt.eprintfln("app: unknown subcommand %q", name)
	usage()
}

usage :: proc() -> ! {
	fmt.eprintln("usage: app <subcommand>")
	fmt.eprintln("subcommands:")
	for command in COMMANDS {
		fmt.eprintfln("  %s", command.name)
	}
	os.exit(2)
}
