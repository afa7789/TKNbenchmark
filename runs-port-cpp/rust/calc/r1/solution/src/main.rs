//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value or
//! `error`. Parsing uses an explicit operator stack (shunting-yard) rather than
//! recursion, so arbitrarily deep nesting cannot overflow the call stack.

mod eval;

use std::io::{self, Read, Write};

use eval::Evaluator;

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut evaluator = Evaluator::default();
    let mut output = String::with_capacity(input.len());

    for line in input.split(|&b| b == b'\n').filter(|line| !is_blank(line)) {
        match evaluator.evaluate(line) {
            Ok(value) => {
                use std::fmt::Write as _;
                // Writing to a String cannot fail.
                let _ = writeln!(output, "{value}");
            }
            Err(_) => output.push_str("error\n"),
        }
    }

    let mut stdout = io::stdout().lock();
    stdout.write_all(output.as_bytes())?;
    stdout.flush()
}
