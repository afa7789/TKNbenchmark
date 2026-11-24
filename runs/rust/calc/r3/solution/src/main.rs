//! `calc`: a 64-bit signed integer expression evaluator.
//!
//! Reads expressions from standard input, one per line, and prints each
//! result (or `error`) on its own line. Blank lines produce no output.

mod eval;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());

    for line in input.split(|&b| b == b'\n') {
        if is_blank(line) {
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
        // A closed stdout (e.g. piping into `head`) is not worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("calc: {e}");
            ExitCode::FAILURE
        }
    }
}
