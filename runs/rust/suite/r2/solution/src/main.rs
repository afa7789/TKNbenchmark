//! `suite`: a command-line program with three independent subcommands.
//!
//! - `wordfreq`: the ten most frequent words of standard input.
//! - `lru`: an LRU cache simulator driven by commands on standard input.
//! - `calc`: a 64-bit signed integer expression evaluator, one expression per line.

mod calc;
mod lru;
mod wordfreq;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

type Command = fn(&[u8], &mut dyn Write) -> io::Result<()>;

fn main() -> ExitCode {
    let name = std::env::args().nth(1);
    let command: Command = match name.as_deref() {
        Some("wordfreq") => wordfreq::run,
        Some("lru") => lru::run,
        Some("calc") => calc::run,
        _ => {
            eprintln!("usage: app <wordfreq|lru|calc>  (reads standard input)");
            return ExitCode::from(2);
        }
    };

    match execute(command) {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piping into `head`) is not a failure of the program.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("app: {e}");
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
