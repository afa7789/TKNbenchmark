//! Command-line front end: evaluates one expression per line of standard input
//! and prints its value, or `error`.

mod eval;

use std::io::{self, BufRead, BufWriter, Write};
use std::process::ExitCode;

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

fn run(input: impl BufRead, output: impl Write) -> io::Result<()> {
    let mut out = BufWriter::new(output);
    for line in input.split(b'\n') {
        let line = line?;
        if is_blank(&line) {
            continue;
        }
        match eval::evaluate(&line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let stdin = io::stdin();
    let stdout = io::stdout();
    match run(stdin.lock(), stdout.lock()) {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piped into `head`) is not a failure worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("calc: {e}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::run;

    fn run_str(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n";
        assert_eq!(run_str(input), "7\n-3\nerror\nerror\n");
    }

    #[test]
    fn blank_lines_are_skipped() {
        assert_eq!(run_str("\n  42  \n\t\n1+1"), "42\n2\n");
    }

    #[test]
    fn carriage_return_is_an_error() {
        assert_eq!(run_str("1\r\n"), "error\n");
    }
}
