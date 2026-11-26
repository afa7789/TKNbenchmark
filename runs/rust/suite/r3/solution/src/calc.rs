//! `calc`: evaluate one 64-bit signed integer expression per input line.
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! Evaluation uses an operator-precedence (shunting-yard) parser with explicit
//! stacks, so arbitrarily deep nesting cannot overflow the call stack.

use std::io::{self, Write};

pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    let mut evaluator = Evaluator::default();
    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|&b| b == b' ' || b == b'\t') {
            continue;
        }
        match evaluator.eval(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Syntax,
    DivisionByZero,
    Overflow,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
    /// An open parenthesis; only ever lives on the operator stack.
    Open,
}

impl Op {
    fn binary(byte: u8) -> Option<Self> {
        Some(match byte {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    fn precedence(self) -> u8 {
        match self {
            Self::Open => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
            Self::Neg => 3,
        }
    }
}

/// Reusable evaluation state; the stacks keep their allocations across lines.
#[derive(Default)]
pub struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    pub fn eval(&mut self, line: &[u8]) -> Result<i64, Error> {
        self.values.clear();
        self.ops.clear();

        // `true` when the grammar requires an operand next (start, after an operator or '(').
        let mut expect_operand = true;
        let mut i = 0;
        while i < line.len() {
            let byte = line[i];
            match byte {
                b' ' | b'\t' => i += 1,
                b'0'..=b'9' if expect_operand => {
                    let len = line[i..]
                        .iter()
                        .position(|b| !b.is_ascii_digit())
                        .unwrap_or(line.len() - i);
                    self.values.push(parse_number(&line[i..i + len])?);
                    i += len;
                    expect_operand = false;
                }
                b'-' if expect_operand => {
                    self.ops.push(Op::Neg);
                    i += 1;
                }
                b'(' if expect_operand => {
                    self.ops.push(Op::Open);
                    i += 1;
                }
                b')' if !expect_operand => {
                    loop {
                        match self.ops.pop() {
                            Some(Op::Open) => break,
                            Some(op) => self.apply(op)?,
                            None => return Err(Error::Syntax),
                        }
                    }
                    i += 1;
                }
                _ if !expect_operand => {
                    let op = Op::binary(byte).ok_or(Error::Syntax)?;
                    // Left associativity: reduce everything that binds at least as tightly.
                    while let Some(&top) = self.ops.last()
                        && top.precedence() >= op.precedence()
                    {
                        self.ops.pop();
                        self.apply(top)?;
                    }
                    self.ops.push(op);
                    i += 1;
                    expect_operand = true;
                }
                _ => return Err(Error::Syntax),
            }
        }

        if expect_operand {
            return Err(Error::Syntax);
        }
        while let Some(op) = self.ops.pop() {
            if op == Op::Open {
                return Err(Error::Syntax);
            }
            self.apply(op)?;
        }
        match self.values[..] {
            [value] => Ok(value),
            _ => Err(Error::Syntax),
        }
    }

    fn apply(&mut self, op: Op) -> Result<(), Error> {
        let rhs = self.values.pop().ok_or(Error::Syntax)?;
        let result = if op == Op::Neg {
            rhs.checked_neg().ok_or(Error::Overflow)?
        } else {
            let lhs = self.values.pop().ok_or(Error::Syntax)?;
            binary(op, lhs, rhs)?
        };
        self.values.push(result);
        Ok(())
    }
}

fn binary(op: Op, lhs: i64, rhs: i64) -> Result<i64, Error> {
    match op {
        Op::Add => lhs.checked_add(rhs).ok_or(Error::Overflow),
        Op::Sub => lhs.checked_sub(rhs).ok_or(Error::Overflow),
        Op::Mul => lhs.checked_mul(rhs).ok_or(Error::Overflow),
        Op::Div if rhs == 0 => Err(Error::DivisionByZero),
        Op::Div => lhs.checked_div(rhs).ok_or(Error::Overflow),
        Op::Rem if rhs == 0 => Err(Error::DivisionByZero),
        // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
        Op::Rem => Ok(lhs.wrapping_rem(rhs)),
        Op::Neg | Op::Open => unreachable!("{op:?} is not a binary operator"),
    }
}

fn parse_number(digits: &[u8]) -> Result<i64, Error> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|acc| acc.checked_add(i64::from(d - b'0')))
            .ok_or(Error::Overflow)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(line: &str) -> Result<i64, Error> {
        Evaluator::default().eval(line.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("2*(3+4)*5"), Ok(70));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("- 7 % 3"), Ok(-1));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(Error::Overflow)
        );
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("3037000500 * 3037000500"), Err(Error::Overflow));
        assert_eq!(eval("000000000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for line in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 -", "1 * * 2", "1 (2)",
            "(1)2", "1 x",
        ] {
            assert_eq!(eval(line), Err(Error::Syntax), "{line:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 200_000;
        let line = format!("{}1{}", "(-".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&line), Ok(1));
    }

    #[test]
    fn blank_lines_print_nothing() {
        let mut out = Vec::new();
        run(b"\n  42  \n\t\n1+1\n1/0", &mut out).unwrap();
        assert_eq!(out, b"42\n2\nerror\n");
    }
}
