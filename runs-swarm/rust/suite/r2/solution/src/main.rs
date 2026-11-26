//! `app`: a suite of independent subcommands that read stdin and write stdout.
//!
//! Each subcommand lives in its own module and exposes a single entry point,
//! `run() -> io::Result<()>`, which owns its I/O end to end.

mod calc;
mod lru;
mod wordfreq;

use std::env;
use std::io;
use std::process::ExitCode;

type EntryPoint = fn() -> io::Result<()>;

const SUBCOMMANDS: &[(&str, EntryPoint)] = &[
    ("wordfreq", wordfreq::run),
    ("lru", lru::run),
    ("calc", calc::run),
];

fn usage() -> String {
    let names: Vec<&str> = SUBCOMMANDS.iter().map(|&(name, _)| name).collect();
    format!("usage: app <{}>", names.join("|"))
}

fn main() -> ExitCode {
    let Some(command) = env::args().nth(1) else {
        eprintln!("{}", usage());
        return ExitCode::from(2);
    };

    let Some(&(_, run)) = SUBCOMMANDS.iter().find(|&&(name, _)| name == command) else {
        eprintln!("app: unknown subcommand '{command}'\n{}", usage());
        return ExitCode::from(2);
    };

    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. `app wordfreq | head`) is not a failure.
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("app {command}: {err}");
            ExitCode::FAILURE
        }
    }
}
