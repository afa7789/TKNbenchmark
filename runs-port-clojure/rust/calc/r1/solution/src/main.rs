//! 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value,
//! or `error`. Blank lines (only spaces/tabs) produce no output.

mod eval;

use std::io::{self, BufRead, BufWriter, Write};

fn run(input: impl BufRead, mut out: impl Write) -> io::Result<()> {
    // Lines are split on `\n` only, so a stray `\r` is a syntax error.
    for line in input.split(b'\n') {
        let line = line?;
        if eval::is_blank_line(&line) {
            continue;
        }
        match eval::evaluate(&line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() {
    let stdin = io::stdin().lock();
    let stdout = BufWriter::with_capacity(64 * 1024, io::stdout().lock());
    if let Err(err) = run(stdin, stdout) {
        // A closed stdout (e.g. piping into `head`) is not worth reporting.
        if err.kind() != io::ErrorKind::BrokenPipe {
            eprintln!("calc: {err}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::run;

    fn output(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n";
        assert_eq!(output(input), "7\n-3\nerror\nerror\n");
    }

    #[test]
    fn blank_lines_and_missing_final_newline() {
        assert_eq!(output("\n  42  \n\t\n1+1"), "42\n2\n");
    }

    #[test]
    fn invalid_bytes_are_errors() {
        let mut out = Vec::new();
        run(&b"1\xff\n1\r\n"[..], &mut out).unwrap();
        assert_eq!(out, b"error\nerror\n");
    }
}
