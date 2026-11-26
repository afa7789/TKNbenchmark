//! `app calc`: 64-bit integer expression evaluator. See the `calc` section of SPEC.md.
//!
//! Each line is parsed and evaluated in a single pass by an operator-precedence
//! (shunting-yard) parser that keeps explicit operand and operator stacks. Unlike
//! a recursive-descent parser, its native stack usage does not grow with nesting
//! depth, so pathological inputs such as a million `(` or `-` cannot overflow it.

use std::fmt;
use std::io::{self, BufRead, Write};

/// Entry point for `app calc`: reads `input` to completion and writes the
/// result to `output`. The caller flushes `output`.
pub fn run<R: BufRead, W: Write>(mut input: R, mut output: W) -> io::Result<()> {
    let mut evaluator = Evaluator::default();
    let mut line = Vec::new();

    loop {
        line.clear();
        if input.read_until(b'\n', &mut line)? == 0 {
            return Ok(());
        }
        let expr = line.strip_suffix(b"\n").unwrap_or(&line);
        if expr.iter().all(|&b| is_blank(b)) {
            continue;
        }
        match evaluator.eval(expr) {
            Ok(value) => writeln!(output, "{value}")?,
            Err(_) => output.write_all(b"error\n")?,
        }
    }
}

/// Why an expression has no value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or an intermediate result is outside the `i64` range.
    Overflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Error::Syntax => "syntax error",
            Error::DivisionByZero => "division by zero",
            Error::Overflow => "overflow",
        })
    }
}

impl std::error::Error for Error {}

/// An entry of the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
    /// An open parenthesis: a barrier that reductions never cross.
    LParen,
}

impl Op {
    /// Binding strength; higher binds tighter. Unary minus binds tightest.
    fn precedence(self) -> u8 {
        match self {
            Op::LParen => 0,
            Op::Add | Op::Sub => 1,
            Op::Mul | Op::Div | Op::Rem => 2,
            Op::Neg => 3,
        }
    }

    fn binary(byte: u8) -> Option<Op> {
        Some(match byte {
            b'+' => Op::Add,
            b'-' => Op::Sub,
            b'*' => Op::Mul,
            b'/' => Op::Div,
            b'%' => Op::Rem,
            _ => return None,
        })
    }
}

/// Reusable expression evaluator. Holding the stacks across lines avoids
/// reallocating them for every expression.
#[derive(Debug, Default)]
pub struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    /// Parses and evaluates one expression (without its line terminator).
    pub fn eval(&mut self, expr: &[u8]) -> Result<i64, Error> {
        self.values.clear();
        self.ops.clear();

        // Whether the parser is positioned where an operand (number, `(` or
        // unary `-`) is expected, as opposed to a binary operator or `)`.
        let mut expect_operand = true;
        let mut i = 0;

        while i < expr.len() {
            let byte = expr[i];
            if is_blank(byte) {
                i += 1;
                continue;
            }

            if expect_operand {
                match byte {
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&expr[i..])?;
                        self.values.push(value);
                        i += len;
                        expect_operand = false;
                        continue;
                    }
                    b'-' => self.ops.push(Op::Neg),
                    b'(' => self.ops.push(Op::LParen),
                    _ => return Err(Error::Syntax),
                }
            } else {
                match byte {
                    b')' => {
                        self.reduce_while(|_| true)?;
                        if self.ops.pop() != Some(Op::LParen) {
                            return Err(Error::Syntax);
                        }
                    }
                    _ => {
                        let op = Op::binary(byte).ok_or(Error::Syntax)?;
                        // Left associativity: reduce operators that bind at
                        // least as tightly before pushing this one.
                        let precedence = op.precedence();
                        self.reduce_while(|top| top.precedence() >= precedence)?;
                        self.ops.push(op);
                        expect_operand = true;
                    }
                }
            }
            i += 1;
        }

        if expect_operand {
            return Err(Error::Syntax);
        }
        self.reduce_while(|_| true)?;
        if !self.ops.is_empty() {
            // An unmatched `(` remains.
            return Err(Error::Syntax);
        }
        debug_assert_eq!(self.values.len(), 1);
        self.values.pop().ok_or(Error::Syntax)
    }

    /// Applies stacked operators, innermost first, while `pred` accepts the
    /// top one. Never crosses an open parenthesis.
    fn reduce_while(&mut self, pred: impl Fn(Op) -> bool) -> Result<(), Error> {
        while let Some(&op) = self.ops.last() {
            if op == Op::LParen || !pred(op) {
                break;
            }
            self.ops.pop();
            self.apply(op)?;
        }
        Ok(())
    }

    /// Applies `op` to the operands on top of the value stack.
    fn apply(&mut self, op: Op) -> Result<(), Error> {
        // The parser only reduces an operator once all its operands have been
        // pushed, so the value stack cannot underflow here.
        const INVARIANT: &str = "operand stack underflow";

        let rhs = self.values.pop().expect(INVARIANT);
        let result = if op == Op::Neg {
            rhs.checked_neg().ok_or(Error::Overflow)?
        } else {
            let lhs = self.values.pop().expect(INVARIANT);
            binary(op, lhs, rhs)?
        };
        self.values.push(result);
        Ok(())
    }
}

/// Evaluates a binary operator with the checked semantics of the spec.
fn binary(op: Op, lhs: i64, rhs: i64) -> Result<i64, Error> {
    let result = match op {
        Op::Add => lhs.checked_add(rhs),
        Op::Sub => lhs.checked_sub(rhs),
        Op::Mul => lhs.checked_mul(rhs),
        Op::Div | Op::Rem if rhs == 0 => return Err(Error::DivisionByZero),
        Op::Div => lhs.checked_div(rhs),
        // `i64::MIN % -1` is mathematically 0, which `wrapping_rem` yields.
        Op::Rem => Some(lhs.wrapping_rem(rhs)),
        Op::Neg | Op::LParen => unreachable!("{op:?} is not a binary operator"),
    };
    result.ok_or(Error::Overflow)
}

/// Parses the maximal run of ASCII digits at the start of `bytes` (which must
/// begin with a digit), returning its value and length.
fn parse_number(bytes: &[u8]) -> Result<(i64, usize), Error> {
    let len = bytes.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = bytes[..len].iter().try_fold(0i64, |acc, &digit| {
        acc.checked_mul(10)?.checked_add(i64::from(digit - b'0'))
    });
    value.map(|value| (value, len)).ok_or(Error::Overflow)
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(expr: &str) -> Result<i64, Error> {
        Evaluator::default().eval(expr.as_bytes())
    }

    fn run_str(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("2 - -3 * 4"), Ok(14));
        assert_eq!(eval("-2 * 3"), Ok(-6));
    }

    #[test]
    fn division_and_remainder() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("1 % (2 - 2)"), Err(Error::DivisionByZero));
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
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("4611686018427387904 * 2"), Err(Error::Overflow));
        assert_eq!(eval("00000000000000000000000000042"), Ok(42));
    }

    #[test]
    fn syntax_errors() {
        for expr in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 (2)", "(1)2", "1 ** 2",
            "1\r", "-",
        ] {
            assert_eq!(eval(expr), Err(Error::Syntax), "{expr:?}");
        }
    }

    #[test]
    fn deep_nesting_does_not_overflow_the_stack() {
        let depth = 1_000_000;
        let nested = format!("{}7{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&nested), Ok(7));
        let negated = format!("{}7", "-".repeat(depth));
        assert_eq!(eval(&negated), Ok(7));
    }

    #[test]
    fn lines() {
        assert_eq!(run_str("\n  42  \n\t\n1+1\n"), "42\n2\n");
        assert_eq!(run_str("1 +\n2 * 3"), "error\n6\n");
        assert_eq!(run_str(""), "");
    }
}
