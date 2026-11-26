//! `calc`: reads one integer expression per line from stdin and prints its
//! value, or `error`. Blank lines produce no output.

mod calc;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    for line in input.split(|&b| b == b'\n') {
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
    let mut input = Vec::new();
    let result = io::stdin()
        .lock()
        .read_to_end(&mut input)
        .and_then(|_| run(&input, &mut BufWriter::new(io::stdout().lock())));
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("calc: {e}");
            ExitCode::FAILURE
        }
    }
}
