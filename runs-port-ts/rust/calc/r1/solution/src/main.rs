//! `calc`: reads one integer expression per line from standard input and
//! prints its value, or `error`, for each non-blank line.

mod eval;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn is_blank_line(line: &[u8]) -> bool {
    line.iter().all(|&b| eval::is_blank(b))
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    if input.is_empty() {
        return Ok(());
    }
    // A trailing newline terminates the last line rather than starting a new one.
    let body = input.strip_suffix(b"\n").unwrap_or(&input);
    for line in body.split(|&b| b == b'\n') {
        if is_blank_line(line) {
            continue;
        }
        match eval::evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piped into `head`) is not worth reporting.
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("calc: {err}");
            ExitCode::FAILURE
        }
    }
}
