//! Command-line entry point: evaluates one expression per line of standard input
//! and prints its value, or `error`.

mod eval;

use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;
use std::thread;

/// Deeply nested expressions are parsed recursively, so give the worker a generous stack.
const STACK_SIZE_BYTES: usize = 1 << 30;

fn run(input: impl BufRead, output: impl Write) -> io::Result<()> {
    let mut input = input;
    let mut out = BufWriter::with_capacity(1 << 16, output);
    let mut line = Vec::with_capacity(256);
    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            break;
        }
        let expr = line.strip_suffix(b"\n").unwrap_or(&line);
        if eval::is_blank(expr) {
            continue;
        }
        match eval::evaluate(expr) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let worker = thread::Builder::new()
        .name("calc".into())
        .stack_size(STACK_SIZE_BYTES)
        .spawn(|| run(io::stdin().lock(), io::stdout().lock()));
    let result = match worker {
        Ok(handle) => handle.join().unwrap_or_else(|_| Err(io::Error::other("worker panicked"))),
        Err(e) => Err(e),
    };
    if let Err(e) = result {
        // A closed stdout is not worth reporting; anything else is.
        if e.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("calc: {e}");
        }
    }
    ExitCode::SUCCESS
}
