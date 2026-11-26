//! `calc`: reads one signed 64-bit integer expression per line from standard
//! input and prints its value, or `error` when it cannot be evaluated.
//!
//! Lines are split on `\n` only; any other byte (including `\r`) is part of
//! the line. Lines that are empty or hold only spaces and tabs print nothing.

mod eval;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

/// Returns `true` for lines that should produce no output.
fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    // A trailing newline does not start another line.
    let input = input.strip_suffix(b"\n").unwrap_or(input);
    for line in input.split(|&b| b == b'\n') {
        if is_blank(line) {
            continue;
        }
        match eval::evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("calc: failed to read standard input: {err}");
        return ExitCode::FAILURE;
    }

    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    match run(&input, &mut out) {
        Ok(()) => ExitCode::SUCCESS,
        // The reader went away (e.g. `calc | head`); nothing more to do.
        Err(err) if err.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("calc: failed to write output: {err}");
            ExitCode::FAILURE
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
    fn blank_lines_print_nothing() {
        assert_eq!(output("\n  42  \n\t\n1+1\n"), "42\n2\n");
        assert_eq!(output(""), "");
        assert_eq!(output("\n\n"), "");
    }

    #[test]
    fn last_line_without_newline() {
        assert_eq!(output("1\n2"), "1\n2\n");
    }

    #[test]
    fn carriage_return_is_an_error() {
        assert_eq!(output("1\r\n"), "error\n");
    }
}
