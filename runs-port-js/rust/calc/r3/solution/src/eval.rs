//! Expression evaluation.
//!
//! The evaluator is an iterative operator-precedence (shunting-yard) parser,
//! so arbitrarily deep nesting cannot overflow the call stack. Values are
//! computed while parsing; any syntax or arithmetic failure yields an error.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Syntax,
    DivisionByZero,
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

pub type Result<T> = std::result::Result<T, Error>;

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
        Some(match b {
            b'+' => BinOp::Add,
            b'-' => BinOp::Sub,
            b'*' => BinOp::Mul,
            b'/' => BinOp::Div,
            b'%' => BinOp::Rem,
            _ => return None,
        })
    }

    fn precedence(self) -> u8 {
        match self {
            BinOp::Add | BinOp::Sub => 1,
            BinOp::Mul | BinOp::Div | BinOp::Rem => 2,
        }
    }

    fn apply(self, a: i64, b: i64) -> Result<i64> {
        match self {
            BinOp::Add => a.checked_add(b).ok_or(Error::Overflow),
            BinOp::Sub => a.checked_sub(b).ok_or(Error::Overflow),
            BinOp::Mul => a.checked_mul(b).ok_or(Error::Overflow),
            BinOp::Div if b == 0 => Err(Error::DivisionByZero),
            BinOp::Div => a.checked_div(b).ok_or(Error::Overflow),
            BinOp::Rem if b == 0 => Err(Error::DivisionByZero),
            // `i64::MIN % -1` is mathematically 0; only the division overflows.
            BinOp::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

/// Entries on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    LParen,
    Neg,
    Binary(BinOp),
}

impl StackOp {
    fn precedence(self) -> u8 {
        match self {
            StackOp::LParen => 0,
            StackOp::Binary(op) => op.precedence(),
            StackOp::Neg => 3,
        }
    }
}

#[derive(Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Evaluator {
    fn pop_value(&mut self) -> Result<i64> {
        self.values.pop().ok_or(Error::Syntax)
    }

    /// Applies `op` to the operands on top of the value stack.
    fn reduce(&mut self, op: StackOp) -> Result<()> {
        let value = match op {
            StackOp::Neg => self.pop_value()?.checked_neg().ok_or(Error::Overflow)?,
            StackOp::Binary(op) => {
                let b = self.pop_value()?;
                let a = self.pop_value()?;
                op.apply(a, b)?
            }
            StackOp::LParen => return Err(Error::Syntax),
        };
        self.values.push(value);
        Ok(())
    }

    /// Reduces stacked operators whose precedence is at least `min_prec`.
    fn reduce_while(&mut self, min_prec: u8) -> Result<()> {
        while let Some(&top) = self.ops.last() {
            if top == StackOp::LParen || top.precedence() < min_prec {
                break;
            }
            self.ops.pop();
            self.reduce(top)?;
        }
        Ok(())
    }

    fn close_paren(&mut self) -> Result<()> {
        self.reduce_while(1)?;
        match self.ops.pop() {
            Some(StackOp::LParen) => Ok(()),
            _ => Err(Error::Syntax),
        }
    }

    fn finish(mut self) -> Result<i64> {
        while let Some(op) = self.ops.pop() {
            self.reduce(op)?;
        }
        match self.values.as_slice() {
            &[value] => Ok(value),
            _ => Err(Error::Syntax),
        }
    }
}

/// Parses a run of ASCII digits as a non-negative `i64`.
fn parse_literal(digits: &[u8]) -> Result<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(Error::Overflow)
    })
}

/// Evaluates a single expression line.
pub fn evaluate(line: &[u8]) -> Result<i64> {
    let mut eval = Evaluator::default();
    let mut expect_operand = true;
    let mut i = 0;

    while i < line.len() {
        let c = line[i];
        i += 1;
        match c {
            b' ' | b'\t' => {}
            b'0'..=b'9' if expect_operand => {
                let start = i - 1;
                while line.get(i).is_some_and(u8::is_ascii_digit) {
                    i += 1;
                }
                eval.values.push(parse_literal(&line[start..i])?);
                expect_operand = false;
            }
            b'-' if expect_operand => eval.ops.push(StackOp::Neg),
            b'(' if expect_operand => eval.ops.push(StackOp::LParen),
            b')' if !expect_operand => eval.close_paren()?,
            _ if !expect_operand => {
                let op = BinOp::from_byte(c).ok_or(Error::Syntax)?;
                eval.reduce_while(op.precedence())?;
                eval.ops.push(StackOp::Binary(op));
                expect_operand = true;
            }
            _ => return Err(Error::Syntax),
        }
    }

    if expect_operand {
        return Err(Error::Syntax);
    }
    eval.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("2*(3+4)*5"), Ok(70));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("-2 * 3"), Ok(-6));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(Error::DivisionByZero));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(Error::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("00000000000000000000000009223372036854775807"), Ok(i64::MAX));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1 + 2\r", "-"] {
            assert_eq!(eval(s), Err(Error::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        let s = format!("{}1", "-".repeat(depth + 1));
        assert_eq!(eval(&s), Ok(-1));
    }
}
