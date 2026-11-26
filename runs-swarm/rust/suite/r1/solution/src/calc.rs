//! `app calc`: 64-bit signed integer expression evaluator: one expression per input line.
//!
//! See the `calc` section of SPEC.md.
//!
//! Expressions are evaluated by an operator-precedence (shunting-yard) parser with explicit
//! stacks rather than recursive descent, so arbitrarily deep nesting such as `((((…))))` or
//! `----…1` cannot overflow the call stack.

use std::io::{self, BufRead, Write};

/// Entry point for `app calc`: reads all of `input` and writes the result to `output`.
///
/// `output` is already buffered and is flushed by the caller.
pub fn run(mut input: impl BufRead, mut output: impl Write) -> io::Result<()> {
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
        match evaluator.evaluate(expr) {
            Ok(value) => writeln!(output, "{value}")?,
            Err(_) => writeln!(output, "error")?,
        }
    }
}

/// Why an expression has no value. All kinds print as `error`; they are kept distinct for
/// clarity and testing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Error {
    Syntax,
    DivisionByZero,
    Overflow,
}

/// An operator waiting on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Neg,
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    /// An open parenthesis: a barrier that reductions never cross.
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

    /// Binding strength; higher binds tighter. `Open` binds loosest so it is never reduced.
    fn precedence(self) -> u8 {
        match self {
            Self::Open => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
            Self::Neg => 3,
        }
    }
}

/// What the parser expects next.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Expect {
    /// A number, `(`, or unary `-`.
    Operand,
    /// A binary operator, `)`, or the end of the line.
    Operator,
}

/// Evaluates expressions, reusing its stacks across calls to avoid per-line allocation.
#[derive(Debug, Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    fn evaluate(&mut self, expr: &[u8]) -> Result<i64, Error> {
        self.values.clear();
        self.ops.clear();

        let mut expect = Expect::Operand;
        let mut i = 0;
        while let Some(&byte) = expr.get(i) {
            i += 1;
            if is_blank(byte) {
                continue;
            }
            match expect {
                Expect::Operand => match byte {
                    b'-' => self.ops.push(Op::Neg),
                    b'(' => self.ops.push(Op::Open),
                    b'0'..=b'9' => {
                        let start = i - 1;
                        let end = expr[start..]
                            .iter()
                            .position(|b| !b.is_ascii_digit())
                            .map_or(expr.len(), |len| start + len);
                        self.values.push(parse_literal(&expr[start..end])?);
                        i = end;
                        expect = Expect::Operator;
                    }
                    _ => return Err(Error::Syntax),
                },
                Expect::Operator => {
                    if byte == b')' {
                        self.reduce_while(|_| true)?;
                        if self.ops.pop() != Some(Op::Open) {
                            return Err(Error::Syntax);
                        }
                    } else {
                        let op = Op::binary(byte).ok_or(Error::Syntax)?;
                        // Left associativity: reduce everything that binds at least as tightly.
                        self.reduce_while(|top| top.precedence() >= op.precedence())?;
                        self.ops.push(op);
                        expect = Expect::Operand;
                    }
                }
            }
        }

        if expect == Expect::Operand {
            return Err(Error::Syntax);
        }
        self.reduce_while(|_| true)?;
        match (self.ops.as_slice(), self.values.as_slice()) {
            ([], &[value]) => Ok(value),
            _ => Err(Error::Syntax),
        }
    }

    /// Applies stacked operators down to the nearest `Open` while `pred` holds for the top one.
    fn reduce_while(&mut self, pred: impl Fn(Op) -> bool) -> Result<(), Error> {
        while let Some(&op) = self.ops.last() {
            if op == Op::Open || !pred(op) {
                break;
            }
            self.ops.pop();
            self.apply(op)?;
        }
        Ok(())
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
    if rhs == 0 && matches!(op, Op::Div | Op::Rem) {
        return Err(Error::DivisionByZero);
    }
    match op {
        Op::Add => lhs.checked_add(rhs),
        Op::Sub => lhs.checked_sub(rhs),
        Op::Mul => lhs.checked_mul(rhs),
        Op::Div => lhs.checked_div(rhs),
        // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
        Op::Rem => Some(lhs.wrapping_rem(rhs)),
        Op::Neg | Op::Open => unreachable!("{op:?} is not a binary operator"),
    }
    .ok_or(Error::Overflow)
}

/// Parses a non-empty run of ASCII digits.
fn parse_literal(digits: &[u8]) -> Result<i64, Error> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|acc| acc.checked_add(i64::from(d - b'0')))
            .ok_or(Error::Overflow)
    })
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(expr: &str) -> Result<i64, Error> {
        Evaluator::default().evaluate(expr.as_bytes())
    }

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
    fn precedence_and_associativity() {
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("- 2 - - 3"), Ok(1));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("1 % (2 - 2)"), Err(Error::DivisionByZero));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(Error::Overflow)
        );
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("4611686018427387904 * 2"), Err(Error::Overflow));
        assert_eq!(eval("0000000000000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for expr in [
            "1 +", "abc", "()", "1 2", "+1", "(1", "1)", ")(", "1 + * 2", "-", "1 -", "2 (3)",
            "(1)(2)", "1\r", "1 ^ 2", "1 2 + 3",
        ] {
            assert_eq!(eval(expr), Err(Error::Syntax), "{expr:?}");
        }
    }

    #[test]
    fn blank_lines_and_missing_final_newline() {
        assert_eq!(run_str("\n  42  \n\t\n1+1"), "42\n2\n");
        assert_eq!(run_str(""), "");
    }

    #[test]
    fn deep_nesting_does_not_overflow_the_stack() {
        let depth = 1_000_000;
        let nested = format!("{}7{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&nested), Ok(7));
        let negated = format!("{}7", "-".repeat(depth + 1));
        assert_eq!(eval(&negated), Ok(-7));
    }
}
