//! calc: a 64-bit signed integer expression evaluator.
//!
//! Reads one expression per line from standard input and prints its value or
//! `error`. Parsing uses an explicit-stack operator-precedence algorithm so
//! that deeply nested input cannot overflow the call stack.

use std::fmt::Write as _;
use std::io::{self, Read, Write};

/// Any failure while evaluating a line: syntax, division by zero or overflow.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EvalError;

type EvalResult<T> = Result<T, EvalError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
    LParen,
}

impl Op {
    fn precedence(self) -> u8 {
        match self {
            Op::LParen => 0,
            Op::Add | Op::Sub => 1,
            Op::Mul | Op::Div | Op::Rem => 2,
            Op::Neg => 3,
        }
    }

    fn binary(byte: u8) -> Option<Op> {
        match byte {
            b'+' => Some(Op::Add),
            b'-' => Some(Op::Sub),
            b'*' => Some(Op::Mul),
            b'/' => Some(Op::Div),
            b'%' => Some(Op::Rem),
            _ => None,
        }
    }

    /// Applies a binary operator with overflow and division-by-zero checks.
    fn apply(self, lhs: i64, rhs: i64) -> Option<i64> {
        match self {
            Op::Add => lhs.checked_add(rhs),
            Op::Sub => lhs.checked_sub(rhs),
            Op::Mul => lhs.checked_mul(rhs),
            Op::Div => lhs.checked_div(rhs),
            // `i64::MIN % -1` is mathematically 0, not an overflow.
            Op::Rem if rhs == -1 => Some(0),
            Op::Rem => lhs.checked_rem(rhs),
            Op::Neg | Op::LParen => unreachable!("not a binary operator: {self:?}"),
        }
    }
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

/// Reusable evaluator; keeps its stacks between lines to avoid reallocating.
#[derive(Debug, Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    /// Returns the value of `line`, or an error on any syntax or arithmetic failure.
    fn evaluate(&mut self, line: &[u8]) -> EvalResult<i64> {
        self.values.clear();
        self.ops.clear();

        let mut expect_operand = true;
        let mut i = 0;

        while i < line.len() {
            let c = line[i];
            if is_blank(c) {
                i += 1;
                continue;
            }
            if expect_operand {
                match c {
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&line[i..])?;
                        self.values.push(value);
                        i += len;
                        expect_operand = false;
                        continue;
                    }
                    b'-' => self.ops.push(Op::Neg),
                    b'(' => self.ops.push(Op::LParen),
                    _ => return Err(EvalError),
                }
            } else if c == b')' {
                while self.ops.last().is_some_and(|&op| op != Op::LParen) {
                    self.reduce()?;
                }
                // Pops the matching '('; none means the ')' is unbalanced.
                self.ops.pop().ok_or(EvalError)?;
            } else {
                let op = Op::binary(c).ok_or(EvalError)?;
                // All binary operators are left-associative.
                while self
                    .ops
                    .last()
                    .is_some_and(|top| top.precedence() >= op.precedence())
                {
                    self.reduce()?;
                }
                self.ops.push(op);
                expect_operand = true;
            }
            i += 1;
        }

        if expect_operand {
            return Err(EvalError); // missing operand (or empty)
        }
        while let Some(&op) = self.ops.last() {
            if op == Op::LParen {
                return Err(EvalError); // unbalanced '('
            }
            self.reduce()?;
        }
        match self.values.as_slice() {
            &[value] => Ok(value),
            _ => Err(EvalError),
        }
    }

    /// Applies the operator on top of the stack to the top operand(s).
    fn reduce(&mut self) -> EvalResult<()> {
        let op = self.ops.pop().ok_or(EvalError)?;
        let rhs = self.values.pop().ok_or(EvalError)?;
        let result = if op == Op::Neg {
            rhs.checked_neg()
        } else {
            let lhs = self.values.pop().ok_or(EvalError)?;
            op.apply(lhs, rhs)
        };
        self.values.push(result.ok_or(EvalError)?);
        Ok(())
    }
}

/// Parses the leading run of ASCII digits in `bytes`.
/// Returns the value and the number of bytes consumed.
fn parse_number(bytes: &[u8]) -> EvalResult<(i64, usize)> {
    let len = bytes.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = bytes[..len].iter().try_fold(0i64, |acc, &digit| {
        acc.checked_mul(10)?.checked_add(i64::from(digit - b'0'))
    });
    value.map(|v| (v, len)).ok_or(EvalError)
}

fn run(input: &[u8]) -> String {
    let mut evaluator = Evaluator::default();
    let mut output = String::with_capacity(input.len() / 2 + 64);

    // A trailing '\n' does not start another line.
    let body = input.strip_suffix(b"\n").unwrap_or(input);
    for line in body.split(|&b| b == b'\n') {
        if line.iter().all(|&b| is_blank(b)) {
            continue;
        }
        match evaluator.evaluate(line) {
            Ok(value) => writeln!(output, "{value}").expect("writing to a String cannot fail"),
            Err(EvalError) => output.push_str("error\n"),
        }
    }
    output
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let output = run(&input);

    let mut stdout = io::stdout().lock();
    stdout.write_all(output.as_bytes())?;
    stdout.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(line: &str) -> Option<i64> {
        Evaluator::default().evaluate(line.as_bytes()).ok()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            run(b"1 + 2 * 3\n-7 / 2\n(1 + 2\n9223372036854775807 + 1\n"),
            "7\n-3\nerror\nerror\n"
        );
    }

    #[test]
    fn arithmetic() {
        assert_eq!(eval("10 - 4 - 3"), Some(3));
        assert_eq!(eval("-7 % 3"), Some(-1));
        assert_eq!(eval("7 % -3"), Some(1));
        assert_eq!(eval("--5"), Some(5));
        assert_eq!(eval("-(2 + 3)"), Some(-5));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Some(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), None);
        assert_eq!(eval("-9223372036854775808"), None);
        assert_eq!(eval("1 / 0"), None);
    }

    #[test]
    fn syntax_errors() {
        for line in ["1 +", "abc", "()", "1 2", "+1", ")", "(1))", "1\r"] {
            assert_eq!(eval(line), None, "{line:?}");
        }
    }

    #[test]
    fn blank_lines_and_missing_newline() {
        assert_eq!(run(b"\n  42  \n\t\n1+1"), "42\n2\n");
        assert_eq!(run(b""), "");
    }
}
