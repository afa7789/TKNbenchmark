//! calc — a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value or
//! `error`. Blank lines (only spaces/tabs) produce no output.

mod eval;

use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;

use eval::Evaluator;

fn is_blank_line(line: &[u8]) -> bool {
    line.iter().all(|&b| eval::is_blank(b))
}

fn run() -> io::Result<()> {
    let stdin = io::stdin();
    let mut input = stdin.lock();
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    let mut evaluator = Evaluator::new();
    let mut line = Vec::new();

    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            break;
        }
        let expr = line.strip_suffix(b"\n").unwrap_or(&line);
        if is_blank_line(expr) {
            continue;
        }
        match evaluator.evaluate(expr) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
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
