//! calc: evaluate 64-bit signed integer expressions, one per input line.
//!
//! Each non-blank line of standard input is parsed and evaluated; its value,
//! or `error`, is written to standard output.

mod eval;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| matches!(b, b' ' | b'\t'))
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::new(io::stdout().lock());
    let body = input.strip_suffix(b"\n").unwrap_or(&input);
    for line in body.split(|&b| b == b'\n').filter(|l| !is_blank(l)) {
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
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("calc: {e}");
            ExitCode::FAILURE
        }
    }
}
