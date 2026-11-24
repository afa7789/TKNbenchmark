//! `calc`: a line-oriented evaluator for signed 64-bit integer expressions.
//!
//! Each input line is parsed and evaluated independently; the result (or
//! `error`) is printed on its own line. Blank lines produce no output.

use std::io::{self, BufWriter, Read, Write};

/// Any failure while evaluating a line. The spec only distinguishes
/// "value" from "error", so no further detail is carried.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EvalError;

type Result<T> = std::result::Result<T, EvalError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinOp {
    fn from_byte(b: u8) -> Option<Self> {
        match b {
            b'+' => Some(Self::Add),
            b'-' => Some(Self::Sub),
            b'*' => Some(Self::Mul),
            b'/' => Some(Self::Div),
            b'%' => Some(Self::Rem),
            _ => None,
        }
    }

    fn precedence(self) -> u8 {
        match self {
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> Result<i64> {
        let value = match self {
            Self::Add => lhs.checked_add(rhs),
            Self::Sub => lhs.checked_sub(rhs),
            Self::Mul => lhs.checked_mul(rhs),
            // `checked_div` rejects both a zero divisor and `MIN / -1`.
            Self::Div => lhs.checked_div(rhs),
            // `MIN % -1` is mathematically 0, so only a zero divisor fails.
            Self::Rem if rhs == 0 => None,
            Self::Rem => Some(lhs.wrapping_rem(rhs)),
        };
        value.ok_or(EvalError)
    }
}

/// Entries on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Neg,
    Bin(BinOp),
    LParen,
}

/// An iterative operator-precedence evaluator (shunting-yard with immediate
/// reduction). Being non-recursive, it handles arbitrarily deep nesting
/// without risking a stack overflow.
#[derive(Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    fn evaluate(&mut self, line: &[u8]) -> Result<i64> {
        self.values.clear();
        self.ops.clear();

        // `true` when the grammar requires an operand next (start of input,
        // after an operator, or after an opening parenthesis).
        let mut expect_operand = true;
        let mut i = 0;

        while i < line.len() {
            let b = line[i];
            match b {
                b' ' | b'\t' => i += 1,
                b'0'..=b'9' if expect_operand => {
                    let start = i;
                    while i < line.len() && line[i].is_ascii_digit() {
                        i += 1;
                    }
                    self.values.push(parse_literal(&line[start..i])?);
                    expect_operand = false;
                }
                b'-' if expect_operand => {
                    self.ops.push(Op::Neg);
                    i += 1;
                }
                b'(' if expect_operand => {
                    self.ops.push(Op::LParen);
                    i += 1;
                }
                b')' if !expect_operand => {
                    self.reduce_while(|_| true)?;
                    if self.ops.pop() != Some(Op::LParen) {
                        return Err(EvalError);
                    }
                    i += 1;
                }
                _ if !expect_operand => {
                    let op = BinOp::from_byte(b).ok_or(EvalError)?;
                    // Left associativity: reduce everything that binds at
                    // least as tightly as the incoming operator.
                    self.reduce_while(|top| match top {
                        Op::Neg => true,
                        Op::Bin(prev) => prev.precedence() >= op.precedence(),
                        Op::LParen => false,
                    })?;
                    self.ops.push(Op::Bin(op));
                    expect_operand = true;
                    i += 1;
                }
                _ => return Err(EvalError),
            }
        }

        if expect_operand {
            return Err(EvalError);
        }
        self.reduce_while(|_| true)?;
        if !self.ops.is_empty() {
            // An unmatched '(' remains.
            return Err(EvalError);
        }
        match self.values.as_slice() {
            &[value] => Ok(value),
            _ => Err(EvalError),
        }
    }

    /// Pops and applies operators until an opening parenthesis is on top,
    /// the stack is empty, or `should_reduce` declines the top operator.
    fn reduce_while(&mut self, should_reduce: impl Fn(Op) -> bool) -> Result<()> {
        while let Some(&top) = self.ops.last() {
            if top == Op::LParen || !should_reduce(top) {
                break;
            }
            self.ops.pop();
            self.apply(top)?;
        }
        Ok(())
    }

    fn apply(&mut self, op: Op) -> Result<()> {
        let result = match op {
            Op::Neg => self.pop_value()?.checked_neg().ok_or(EvalError)?,
            Op::Bin(bin) => {
                let rhs = self.pop_value()?;
                let lhs = self.pop_value()?;
                bin.apply(lhs, rhs)?
            }
            Op::LParen => return Err(EvalError),
        };
        self.values.push(result);
        Ok(())
    }

    fn pop_value(&mut self) -> Result<i64> {
        self.values.pop().ok_or(EvalError)
    }
}

/// Parses a non-empty run of ASCII digits, rejecting values above `i64::MAX`.
fn parse_literal(digits: &[u8]) -> Result<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(EvalError)
    })
}

fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| b == b' ' || b == b'\t')
}

fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut evaluator = Evaluator::default();
    let input = input.strip_suffix(b"\n").unwrap_or(input);
    for line in input.split(|&b| b == b'\n') {
        if is_blank(line) {
            continue;
        }
        match evaluator.evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(EvalError) => out.write_all(b"error\n")?,
        }
    }
    Ok(())
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let mut out = BufWriter::new(io::stdout().lock());
    run(&input, &mut out)?;
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Option<i64> {
        Evaluator::default().evaluate(s.as_bytes()).ok()
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Some(7));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Some(5));
        assert_eq!(eval("10 - 4 - 3"), Some(3));
        assert_eq!(eval("2*(3+4)*5"), Some(70));
        assert_eq!(eval("-2 * -3"), Some(6));
        assert_eq!(eval("--5"), Some(5));
        assert_eq!(eval("-(2 + 3)"), Some(-5));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Some(-3));
        assert_eq!(eval("-7 % 3"), Some(-1));
        assert_eq!(eval("7 % -3"), Some(1));
        assert_eq!(eval("1 / 0"), None);
        assert_eq!(eval("1 % 0"), None);
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Some(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), None);
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Some(i64::MAX));
        assert_eq!(eval("9223372036854775808"), None);
        assert_eq!(eval("-9223372036854775808"), None);
        assert_eq!(eval("9223372036854775807 + 1"), None);
        assert_eq!(eval("-(-9223372036854775807 - 1)"), None);
        assert_eq!(eval("3037000500 * 3037000500"), None);
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1", "1)", ")(", "1 - * 2", "1 -", "(1))"] {
            assert_eq!(eval(s), None, "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Some(1));
        let s = format!("{}1", "-".repeat(depth));
        assert_eq!(eval(&s), Some(1));
    }
}
