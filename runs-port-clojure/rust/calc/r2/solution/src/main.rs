//! `calc`: reads one integer expression per line from stdin and prints its
//! value, or `error`, for each non-blank line.

mod eval;

use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;
use std::thread;

/// Deeply nested expressions recurse deeply; evaluate on a generous stack.
const STACK_SIZE: usize = 1 << 30;

/// Writes the result for one line, or nothing if the line is blank.
fn process_line(line: &[u8], out: &mut impl Write) -> io::Result<()> {
    if line.iter().all(|&b| eval::is_blank(b)) {
        return Ok(());
    }
    match eval::evaluate(line) {
        Ok(value) => writeln!(out, "{value}"),
        Err(_) => out.write_all(b"error\n"),
    }
}

fn run() -> io::Result<()> {
    let mut input = io::stdin().lock();
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    let mut buf = Vec::new();
    loop {
        buf.clear();
        if input.read_until(b'\n', &mut buf)? == 0 {
            break;
        }
        // Like Java's `readLine`, treat `\n`, `\r\n` and a lone `\r` as terminators.
        let line = buf.strip_suffix(b"\n").unwrap_or(&buf);
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        for part in line.split(|&b| b == b'\r') {
            process_line(part, &mut out)?;
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let worker = thread::Builder::new()
        .name("calc".into())
        .stack_size(STACK_SIZE)
        .spawn(run);
    let result = match worker {
        Ok(handle) => handle.join().unwrap_or_else(|_| Err(io::Error::other("worker panicked"))),
        Err(e) => Err(e),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout is not an error worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("calc: {e}");
            ExitCode::FAILURE
        }
    }
}
