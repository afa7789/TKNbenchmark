//! `calc`: reads one integer expression per line from standard input and
//! prints its value, or `error`. Blank lines produce no output.

mod calc;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::new(io::stdout().lock());
    // A trailing newline terminates the last line rather than starting a new one.
    let body = input.strip_suffix(b"\n").unwrap_or(&input);
    for line in body.split(|&b| b == b'\n') {
        if calc::is_blank_line(line) {
            continue;
        }
        match calc::evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed pipe downstream is not a failure of the calculator.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("calc: {e}");
            ExitCode::FAILURE
        }
    }
}
