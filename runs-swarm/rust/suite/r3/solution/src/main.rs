//! `app`: a command-line suite of independent subcommands (see SPEC.md).
//!
//! The first argument selects a subcommand. Each subcommand lives in its own
//! module and exposes the same entry point:
//!
//! ```ignore
//! pub fn run<R: BufRead, W: Write>(input: R, output: W) -> io::Result<()>
//! ```
//!
//! `input` is locked standard input; `output` is buffered, locked standard
//! output, flushed by `main` after `run` returns.

mod calc;
mod lru;
mod wordfreq;

use std::env;
use std::io::{self, BufWriter, Write};
use std::process::ExitCode;

const USAGE: &str = "usage: app <wordfreq|lru|calc>";

fn main() -> ExitCode {
    let Some(name) = env::args_os().nth(1) else {
        eprintln!("{USAGE}");
        return ExitCode::from(2);
    };

    let input = io::stdin().lock();
    let mut output = BufWriter::with_capacity(1 << 16, io::stdout().lock());

    let result = match name.to_str() {
        Some("wordfreq") => wordfreq::run(input, &mut output),
        Some("lru") => lru::run(input, &mut output),
        Some("calc") => calc::run(input, &mut output),
        _ => {
            eprintln!("app: unknown subcommand {:?}\n{USAGE}", name.to_string_lossy());
            return ExitCode::from(2);
        }
    };

    match result.and_then(|()| output.flush()) {
        Ok(()) => ExitCode::SUCCESS,
        // A closed downstream pipe is not a failure of ours.
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("app: {err}");
            ExitCode::FAILURE
        }
    }
}
