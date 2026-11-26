//! calc: evaluate one 64-bit signed integer expression per input line.

mod eval;

use std::io::{self, BufWriter, Read, Write};

use eval::Evaluator;

fn is_blank_line(line: &[u8]) -> bool {
    line.iter().all(|&b| eval::is_blank(b))
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout();
    let mut out = BufWriter::with_capacity(1 << 16, stdout.lock());
    let mut evaluator = Evaluator::new();

    for line in input.split(|&b| b == b'\n') {
        if is_blank_line(line) {
            continue;
        }
        match evaluator.evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() {
    if let Err(err) = run() {
        // A closed stdout is not worth reporting; anything else is.
        if err.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("calc: {err}");
            std::process::exit(1);
        }
    }
}
