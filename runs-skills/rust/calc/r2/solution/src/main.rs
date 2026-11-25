//! `calc`: evaluates one 64-bit integer expression per line of standard input.

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("calc: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::new(io::stdout().lock());
    for line in input.split(|&b| b == b'\n') {
        if calc::is_blank(line) {
            continue;
        }
        match calc::evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => writeln!(out, "error")?,
        }
    }
    out.flush()
}
