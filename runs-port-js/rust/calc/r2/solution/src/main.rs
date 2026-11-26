//! `calc`: evaluates one signed 64-bit integer expression per line of stdin.

mod evaluate;

use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;

use evaluate::evaluate;

fn run() -> io::Result<()> {
    let stdin = io::stdin();
    let mut input = stdin.lock();
    let mut out = BufWriter::with_capacity(64 * 1024, io::stdout().lock());
    let mut line = Vec::new();

    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            break;
        }
        if line.last() == Some(&b'\n') {
            line.pop();
        }
        match evaluate(&line) {
            Ok(Some(value)) => writeln!(out, "{value}")?,
            Ok(None) => {}
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
