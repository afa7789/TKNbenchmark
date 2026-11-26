//! `app`: a suite of independent stdin/stdout tools selected by the first argument.
//!
//! Each subcommand lives in its own module and exposes a single entry point:
//!
//! ```ignore
//! pub fn run(input: impl BufRead, output: impl Write) -> io::Result<()>
//! ```
//!
//! `main` owns process concerns only: argument dispatch, locking and buffering
//! the standard streams, flushing, and mapping errors to an exit status.

mod calc;
mod lru;
mod wordfreq;

use std::env;
use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;

type Entry = fn(&mut dyn BufRead, &mut dyn Write) -> io::Result<()>;

const SUBCOMMANDS: &[(&str, Entry)] = &[
    ("wordfreq", |i, o| wordfreq::run(i, o)),
    ("lru", |i, o| lru::run(i, o)),
    ("calc", |i, o| calc::run(i, o)),
];

fn usage() -> String {
    let names: Vec<&str> = SUBCOMMANDS.iter().map(|&(name, _)| name).collect();
    format!("usage: app <{}>", names.join("|"))
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let (Some(command), None) = (args.next(), args.next()) else {
        eprintln!("{}", usage());
        return ExitCode::from(2);
    };
    let Some(&(_, entry)) = SUBCOMMANDS.iter().find(|&&(name, _)| name == command) else {
        eprintln!("app: unknown subcommand '{command}'\n{}", usage());
        return ExitCode::from(2);
    };

    let mut input = io::stdin().lock();
    let mut output = BufWriter::new(io::stdout().lock());
    match entry(&mut input, &mut output).and_then(|()| output.flush()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("app {command}: {err}");
            ExitCode::FAILURE
        }
    }
}
