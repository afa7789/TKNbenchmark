//! `suite`: a command-line program with three independent subcommands.

mod calc;
mod lru;
mod wordfreq;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

type Command = fn(&[u8], &mut dyn Write) -> io::Result<()>;

fn main() -> ExitCode {
    let Some(name) = std::env::args().nth(1) else {
        return usage();
    };
    let command: Command = match name.as_str() {
        "wordfreq" => wordfreq::run,
        "lru" => lru::run,
        "calc" => calc::run,
        _ => return usage(),
    };
    match execute(command) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("app {name}: {err}");
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

fn usage() -> ExitCode {
    eprintln!("usage: app <wordfreq|lru|calc>  (reads standard input)");
    ExitCode::from(2)
}
