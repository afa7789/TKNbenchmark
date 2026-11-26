//! Reads one expression per line from standard input and prints its value or `error`.

mod evaluator;

use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;

fn run(mut input: impl BufRead, mut output: impl Write) -> io::Result<()> {
    let mut line = Vec::new();
    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            break;
        }
        let expression = line.strip_suffix(b"\n").unwrap_or(&line);
        if expression.iter().copied().all(evaluator::is_blank) {
            continue;
        }
        match evaluator::evaluate(expression) {
            Ok(value) => writeln!(output, "{value}")?,
            Err(_) => output.write_all(b"error\n")?,
        }
    }
    output.flush()
}

fn main() -> ExitCode {
    let stdin = io::stdin().lock();
    let stdout = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    match run(stdin, stdout) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("calc: {err}");
            ExitCode::FAILURE
        }
    }
}
