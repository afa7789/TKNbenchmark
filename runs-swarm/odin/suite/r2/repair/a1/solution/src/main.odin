// Entry point of `app`: dispatches the first argument to a subcommand.
// Each subcommand lives in its own package under src/ and exposes `run`.
package main

import "core:fmt"
import "core:os"

import "calc"
import "lru"
import "wordfreq"

Subcommand :: struct {
	name: string,
	run:  proc(),
}

SUBCOMMANDS :: [?]Subcommand {
	{"wordfreq", wordfreq.run},
	{"lru",      lru.run},
	{"calc",     calc.run},
}

main :: proc() {
	if len(os.args) < 2 {
		usage()
		os.exit(2)
	}

	name := os.args[1]
	for cmd in SUBCOMMANDS {
		if cmd.name == name {
			cmd.run()
			return
		}
	}

	fmt.eprintfln("app: unknown subcommand %q", name)
	usage()
	os.exit(2)
}

usage :: proc() {
	fmt.eprintln("usage: app <subcommand>")
	fmt.eprintln("subcommands:")
	for cmd in SUBCOMMANDS {
		fmt.eprintfln("  %s", cmd.name)
	}
}
