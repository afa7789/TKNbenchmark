//! `app calc`: a 64-bit signed integer expression evaluator (see SPEC.md, section `calc`).
//!
//! Each input line is evaluated independently. The evaluator is an operator-precedence
//! (shunting-yard) parser driven by explicit stacks rather than recursion, so arbitrarily
//! deep nesting such as `((((…))))` or `- - - … 1` cannot overflow the call stack.

use std::io::{self, BufWriter, Read, Write};

/// Entry point for `app calc`: reads standard input, writes standard output.
pub fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let stdout = io::stdout().lock();
    let mut out = BufWriter::new(stdout);
    let mut evaluator = Evaluator::default();

    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|&b| is_blank(b)) {
            continue;
        }
        match evaluator.eval(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    out.flush()
}

/// Why an expression has no value. All variants print as `error`; the distinction
/// exists for clarity and testing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    Syntax,
    DivisionByZero,
    Overflow,
}

type CalcResult<T> = Result<T, CalcError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinaryOp {
    fn from_byte(b: u8) -> Option<Self> {
        Some(match b {
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
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> CalcResult<i64> {
        match self {
            Self::Add => lhs.checked_add(rhs).ok_or(CalcError::Overflow),
            Self::Sub => lhs.checked_sub(rhs).ok_or(CalcError::Overflow),
            Self::Mul => lhs.checked_mul(rhs).ok_or(CalcError::Overflow),
            Self::Div | Self::Rem if rhs == 0 => Err(CalcError::DivisionByZero),
            // The only remaining failure is i64::MIN / -1.
            Self::Div => lhs.checked_div(rhs).ok_or(CalcError::Overflow),
            // i64::MIN % -1 is mathematically 0, which `wrapping_rem` yields.
            Self::Rem => Ok(lhs.wrapping_rem(rhs)),
        }
    }
}

/// An entry on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Binary(BinaryOp),
    /// Prefix negation; binds tighter than any binary operator.
    Negate,
    /// An open parenthesis acting as a barrier.
    LParen,
}

/// Reusable evaluator; keeps its stack allocations across lines.
#[derive(Debug, Default)]
pub struct Evaluator {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Evaluator {
    /// Evaluates one expression (without its line terminator).
    pub fn eval(&mut self, expr: &[u8]) -> CalcResult<i64> {
        self.values.clear();
        self.ops.clear();

        let mut pos = 0;
        // True when the grammar expects an operand (number, `(` or unary `-`) next.
        let mut expect_operand = true;

        while let Some(&b) = expr.get(pos) {
            if is_blank(b) {
                pos += 1;
                continue;
            }

            if expect_operand {
                match b {
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&expr[pos..])?;
                        self.values.push(value);
                        pos += len;
                        expect_operand = false;
                        continue;
                    }
                    b'-' => self.ops.push(StackOp::Negate),
                    b'(' => self.ops.push(StackOp::LParen),
                    _ => return Err(CalcError::Syntax),
                }
            } else if let Some(op) = BinaryOp::from_byte(b) {
                // Left associativity: reduce everything of equal or higher precedence.
                self.reduce_while(|top| match top {
                    StackOp::Negate => true,
                    StackOp::Binary(prev) => prev.precedence() >= op.precedence(),
                    StackOp::LParen => false,
                })?;
                self.ops.push(StackOp::Binary(op));
                expect_operand = true;
            } else if b == b')' {
                self.reduce_while(|top| top != StackOp::LParen)?;
                if self.ops.pop() != Some(StackOp::LParen) {
                    return Err(CalcError::Syntax);
                }
            } else {
                return Err(CalcError::Syntax);
            }
            pos += 1;
        }

        if expect_operand {
            // Empty input or a dangling operator / `(` / `-`.
            return Err(CalcError::Syntax);
        }
        self.reduce_while(|top| top != StackOp::LParen)?;
        if !self.ops.is_empty() {
            return Err(CalcError::Syntax);
        }
        match self.values[..] {
            [value] => Ok(value),
            _ => unreachable!("a complete expression reduces to exactly one value"),
        }
    }

    /// Pops and applies operators while `pred` holds for the top of the operator stack.
    fn reduce_while(&mut self, pred: impl Fn(StackOp) -> bool) -> CalcResult<()> {
        while let Some(&top) = self.ops.last() {
            if !pred(top) {
                break;
            }
            self.ops.pop();
            self.apply(top)?;
        }
        Ok(())
    }

    fn apply(&mut self, op: StackOp) -> CalcResult<()> {
        // The parser state machine guarantees operands are present whenever an
        // operator is reduced, so a missing value is an internal invariant violation.
        const INVARIANT: &str = "operator reduced without its operands";
        let result = match op {
            StackOp::Negate => {
                let value = self.values.pop().expect(INVARIANT);
                value.checked_neg().ok_or(CalcError::Overflow)?
            }
            StackOp::Binary(op) => {
                let rhs = self.values.pop().expect(INVARIANT);
                let lhs = self.values.pop().expect(INVARIANT);
                op.apply(lhs, rhs)?
            }
            StackOp::LParen => unreachable!("parentheses are never applied"),
        };
        self.values.push(result);
        Ok(())
    }
}

/// Parses the maximal run of ASCII digits at the start of `digits` (which must begin
/// with one). Returns the value and the number of bytes consumed.
fn parse_number(digits: &[u8]) -> CalcResult<(i64, usize)> {
    let len = digits.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = digits[..len].iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|acc| acc.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })?;
    Ok((value, len))
}

fn is_blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> CalcResult<i64> {
        Evaluator::default().eval(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("\t42 "), Ok(42));
        assert_eq!(eval("007"), Ok(7));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("5 % (2 - 2)"), Err(CalcError::DivisionByZero));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("- - - 1"), Ok(-1));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(CalcError::Overflow));
        assert_eq!(
            eval("-(-9223372036854775807 - 1)"),
            Err(CalcError::Overflow)
        );
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(CalcError::Overflow)
        );
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("4611686018427387904 * 2"), Err(CalcError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for bad in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 -", "-", "(", "1 ** 2",
            "1\r", "2(3)", "(1)(2)",
        ] {
            assert_eq!(eval(bad), Err(CalcError::Syntax), "{bad:?}");
        }
    }

    #[test]
    fn deep_nesting_does_not_recurse() {
        let depth = 1_000_000;
        let expr = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&expr), Ok(1));
        let negs = format!("{}7", "-".repeat(depth));
        assert_eq!(eval(&negs), Ok(7));
    }
}
