//! `calc`: a 64-bit signed integer expression evaluator.
//!
//! Reads expressions from standard input, one per line, and prints each
//! value or `error`. Blank lines (only spaces/tabs) produce no output.

mod eval;

use std::io::{self, BufWriter, Read, Write};

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let input = input.strip_suffix(b"\n").unwrap_or(input);
    if input.is_empty() {
        return Ok(());
    }
    for line in input.split(|&b| b == b'\n') {
        if is_blank(line) {
            continue;
        }
        match eval::evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    Ok(())
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    run(&input, &mut out)?;
    out.flush()
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
        assert_eq!(
            output("1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n"),
            "7\n-3\nerror\nerror\n"
        );
    }

    #[test]
    fn blank_lines_and_missing_trailing_newline() {
        assert_eq!(output("\n  42  \n\t\n1+1"), "42\n2\n");
        assert_eq!(output(""), "");
        assert_eq!(output("\n"), "");
    }
}
