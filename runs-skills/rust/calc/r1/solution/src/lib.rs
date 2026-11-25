//! A 64-bit signed integer expression evaluator.
//!
//! Parsing uses an iterative shunting-yard algorithm, so arbitrarily deep
//! nesting cannot overflow the call stack.

use std::fmt;

/// Reasons an expression fails to evaluate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result is outside the `i64` range.
    Overflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for Error {}

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

    fn apply(self, a: i64, b: i64) -> Result<i64, Error> {
        match self {
            Self::Add => a.checked_add(b).ok_or(Error::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(Error::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(Error::Overflow),
            Self::Div | Self::Rem if b == 0 => Err(Error::DivisionByZero),
            Self::Div => a.checked_div(b).ok_or(Error::Overflow),
            // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Neg,
    Bin(BinOp),
    LParen,
}

/// Operand and operator stacks of the shunting-yard evaluator.
#[derive(Default)]
struct Machine {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Machine {
    fn pop_value(&mut self) -> Result<i64, Error> {
        self.values.pop().ok_or(Error::Syntax)
    }

    /// Applies `op` to the top of the value stack.
    fn reduce(&mut self, op: StackOp) -> Result<(), Error> {
        let result = match op {
            StackOp::Neg => self.pop_value()?.checked_neg().ok_or(Error::Overflow)?,
            StackOp::Bin(bin) => {
                let b = self.pop_value()?;
                let a = self.pop_value()?;
                bin.apply(a, b)?
            }
            StackOp::LParen => return Err(Error::Syntax),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces pending operators that bind at least as tightly as `bin`
    /// (left associativity), then pushes `bin`.
    fn push_binary(&mut self, bin: BinOp) -> Result<(), Error> {
        while let Some(&top) = self.ops.last() {
            let binds_tighter = match top {
                StackOp::Neg => true,
                StackOp::Bin(prev) => prev.precedence() >= bin.precedence(),
                StackOp::LParen => false,
            };
            if !binds_tighter {
                break;
            }
            self.ops.pop();
            self.reduce(top)?;
        }
        self.ops.push(StackOp::Bin(bin));
        Ok(())
    }

    /// Reduces up to and including the matching `(`.
    fn close_paren(&mut self) -> Result<(), Error> {
        loop {
            match self.ops.pop() {
                Some(StackOp::LParen) => return Ok(()),
                Some(op) => self.reduce(op)?,
                None => return Err(Error::Syntax),
            }
        }
    }

    fn finish(mut self) -> Result<i64, Error> {
        while let Some(op) = self.ops.pop() {
            self.reduce(op)?;
        }
        match self.values.as_slice() {
            &[value] => Ok(value),
            _ => Err(Error::Syntax),
        }
    }
}

/// Parses a decimal literal starting at `*pos`, advancing past it.
fn parse_number(input: &[u8], pos: &mut usize) -> Result<i64, Error> {
    let mut value: i64 = 0;
    while let Some(&b) = input.get(*pos)
        && b.is_ascii_digit()
    {
        value = value
            .checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(b - b'0')))
            .ok_or(Error::Overflow)?;
        *pos += 1;
    }
    Ok(value)
}

/// Evaluates a single expression.
///
/// # Errors
///
/// Returns an [`Error`] on syntax errors, division by zero, or overflow.
///
/// ```
/// assert_eq!(calc::evaluate(b"1 + 2 * 3"), Ok(7));
/// assert!(calc::evaluate(b"(1 + 2").is_err());
/// ```
pub fn evaluate(input: &[u8]) -> Result<i64, Error> {
    let mut machine = Machine::default();
    // True when the next token must start an operand (number, `(` or unary `-`).
    let mut expect_operand = true;
    let mut pos = 0;

    while let Some(&b) = input.get(pos) {
        match b {
            b' ' | b'\t' => pos += 1,
            b'0'..=b'9' if expect_operand => {
                let value = parse_number(input, &mut pos)?;
                machine.values.push(value);
                expect_operand = false;
            }
            b'(' if expect_operand => {
                machine.ops.push(StackOp::LParen);
                pos += 1;
            }
            b'-' if expect_operand => {
                machine.ops.push(StackOp::Neg);
                pos += 1;
            }
            b')' if !expect_operand => {
                machine.close_paren()?;
                pos += 1;
            }
            _ if !expect_operand => {
                let bin = BinOp::from_byte(b).ok_or(Error::Syntax)?;
                machine.push_binary(bin)?;
                expect_operand = true;
                pos += 1;
            }
            _ => return Err(Error::Syntax),
        }
    }

    if expect_operand {
        return Err(Error::Syntax);
    }
    machine.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, Error> {
        evaluate(s.as_bytes())
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
        assert_eq!(eval("- - 1"), Ok(1));
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
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(Error::Overflow)
        );
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("3037000500 * 3037000500"), Err(Error::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 1", "1 -", "1 * * 2",
            "1\r", "(", "-",
        ] {
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
