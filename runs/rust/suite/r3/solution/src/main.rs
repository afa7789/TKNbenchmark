//! `suite`: a command-line program bundling three independent stdin/stdout tools.
//!
//! - `wordfreq`: the ten most frequent ASCII words.
//! - `lru`: an LRU cache simulator.
//! - `calc`: a 64-bit signed integer expression evaluator.

mod calc;
mod fxhash;
mod lru;
mod wordfreq;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const USAGE: &str = "usage: app <wordfreq|lru|calc>  (reads standard input)";

type Command = fn(&[u8], &mut dyn Write) -> io::Result<()>;

fn main() -> ExitCode {
    let Some(name) = std::env::args().nth(1) else {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    };
    let command: Command = match name.as_str() {
        "wordfreq" => wordfreq::run,
        "lru" => lru::run,
        "calc" => calc::run,
        other => {
            eprintln!("unknown subcommand `{other}`\n{USAGE}");
            return ExitCode::from(2);
        }
    };

    match execute(command) {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piping into `head`) is not a failure worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("app {name}: {e}");
            ExitCode::FAILURE
        }
    }
}

fn execute(command: Command) -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    command(&input, &mut out)?;
    out.flush()
}
