//! `calc`: reads one expression per line from standard input and prints its
//! value or `error`. Blank lines produce no output.

mod error;
mod parser;

use std::io::{self, BufRead, BufWriter, Write};
use std::thread;

/// Generous stack so deeply nested expressions do not overflow the recursive parser.
const STACK_SIZE_BYTES: usize = 1 << 30;

fn main() -> io::Result<()> {
    thread::Builder::new()
        .name("calc".into())
        .stack_size(STACK_SIZE_BYTES)
        .spawn(run)?
        .join()
        .expect("calc worker thread panicked")
}

fn run() -> io::Result<()> {
    let stdin = io::stdin().lock();
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());

    // Lines are split on '\n' only, so a '\r' stays in the line and is rejected
    // as an invalid character. Working on raw bytes means arbitrary input never
    // fails decoding.
    for line in stdin.split(b'\n') {
        let line = line?;
        if is_blank(&line) {
            continue;
        }
        match parser::evaluate(&line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&c| matches!(c, b' ' | b'\t'))
}
