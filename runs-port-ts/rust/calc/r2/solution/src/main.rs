//! `calc`: evaluates one signed 64-bit integer expression per line of stdin.

mod calc;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    // A trailing newline terminates the last line rather than starting a new one.
    let body = input.strip_suffix(b"\n").unwrap_or(&input);

    let mut out = BufWriter::new(io::stdout().lock());
    for line in body.split(|&b| b == b'\n') {
        match calc::evaluate_line(line) {
            Some(Ok(value)) => writeln!(out, "{value}")?,
            Some(Err(_)) => out.write_all(b"error\n")?,
            None => {}
        }
    }
    out.flush()
}

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
