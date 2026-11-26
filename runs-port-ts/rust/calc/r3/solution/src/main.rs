//! `calc`: evaluates one signed 64-bit integer expression per line of stdin.

mod evaluate;

use std::io::{self, BufWriter, Read, Write};

use evaluate::{evaluate, is_blank};

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut lines: Vec<&[u8]> = input.split(|&b| b == b'\n').collect();
    if lines.last().is_some_and(|l| l.is_empty()) {
        lines.pop();
    }

    let mut out = BufWriter::new(io::stdout().lock());
    for line in lines.into_iter().filter(|l| !is_blank(l)) {
        match evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() {
    if let Err(err) = run() {
        // A closed stdout (e.g. piping into `head`) is not worth reporting.
        if err.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("calc: {err}");
            std::process::exit(1);
        }
    }
}
