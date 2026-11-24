//! `calc`: evaluates one 64-bit signed integer expression per line of stdin.

mod eval;

use std::io::{self, BufRead, BufWriter, Write};

fn main() -> io::Result<()> {
    let stdin = io::stdin().lock();
    let mut out = BufWriter::new(io::stdout().lock());
    run(stdin, &mut out)?;
    out.flush()
}

/// Processes every line of `input`, writing one result line per non-blank expression.
fn run(mut input: impl BufRead, out: &mut impl Write) -> io::Result<()> {
    let mut line = Vec::new();
    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            return Ok(());
        }
        let expr = line.strip_suffix(b"\n").unwrap_or(&line);
        if expr.iter().all(|&b| b == b' ' || b == b'\t') {
            continue;
        }
        match eval::evaluate(expr) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => writeln!(out, "error")?,
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
        assert_eq!(
            run_str("1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n"),
            "7\n-3\nerror\nerror\n"
        );
    }

    #[test]
    fn blank_lines_and_missing_final_newline() {
        assert_eq!(run_str("\n  42  \n\t\n1+1"), "42\n2\n");
    }
}
