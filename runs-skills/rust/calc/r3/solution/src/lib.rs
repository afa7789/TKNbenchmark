//! A 64-bit signed integer expression evaluator.
//!
//! Grammar:
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! Parsing uses an explicit operator stack (shunting-yard) rather than
//! recursion, so arbitrarily deep nesting cannot overflow the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or an intermediate result is outside the `i64` range.
    Overflow,
}

impl fmt::Display for EvalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for EvalError {}

/// Returns `true` if the line holds only spaces and tabs (or nothing).
#[must_use]
pub fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| is_space(b))
}

const fn is_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t')
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinOp {
    const fn from_byte(b: u8) -> Option<Self> {
        Some(match b {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    const fn precedence(self) -> u8 {
        match self {
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> Result<i64, EvalError> {
        match self {
            Self::Add => lhs.checked_add(rhs).ok_or(EvalError::Overflow),
            Self::Sub => lhs.checked_sub(rhs).ok_or(EvalError::Overflow),
            Self::Mul => lhs.checked_mul(rhs).ok_or(EvalError::Overflow),
            Self::Div | Self::Rem if rhs == 0 => Err(EvalError::DivisionByZero),
            Self::Div => lhs.checked_div(rhs).ok_or(EvalError::Overflow),
            // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
            Self::Rem => Ok(lhs.wrapping_rem(rhs)),
        }
    }
}

/// An entry on the pending-operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pending {
    Neg,
    Bin(BinOp),
    LParen,
}

/// Evaluation state: operand and pending-operator stacks.
#[derive(Debug, Default)]
struct Machine {
    operands: Vec<i64>,
    operators: Vec<Pending>,
}

impl Machine {
    fn pop_operand(&mut self) -> Result<i64, EvalError> {
        self.operands.pop().ok_or(EvalError::Syntax)
    }

    fn reduce(&mut self, op: Pending) -> Result<(), EvalError> {
        let value = match op {
            Pending::Neg => self
                .pop_operand()?
                .checked_neg()
                .ok_or(EvalError::Overflow)?,
            Pending::Bin(bin) => {
                let rhs = self.pop_operand()?;
                let lhs = self.pop_operand()?;
                bin.apply(lhs, rhs)?
            }
            Pending::LParen => return Err(EvalError::Syntax),
        };
        self.operands.push(value);
        Ok(())
    }

    /// Applies every pending operator that binds at least as tightly as a
    /// binary operator of `min_precedence`, stopping at an open parenthesis.
    fn reduce_while_binds(&mut self, min_precedence: u8) -> Result<(), EvalError> {
        while let Some(&top) = self.operators.last() {
            let binds = match top {
                Pending::Neg => true,
                Pending::Bin(op) => op.precedence() >= min_precedence,
                Pending::LParen => false,
            };
            if !binds {
                break;
            }
            self.operators.pop();
            self.reduce(top)?;
        }
        Ok(())
    }
}

/// Parses a decimal literal starting at `*pos`, advancing past it.
fn parse_number(line: &[u8], pos: &mut usize) -> Result<i64, EvalError> {
    let mut value: i64 = 0;
    while let Some(&b) = line.get(*pos)
        && b.is_ascii_digit()
    {
        value = value
            .checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(b - b'0')))
            .ok_or(EvalError::Overflow)?;
        *pos += 1;
    }
    Ok(value)
}

/// Evaluates one expression.
///
/// # Errors
///
/// Returns an [`EvalError`] on a syntax error, division by zero, or overflow.
///
/// # Examples
///
/// ```
/// assert_eq!(calc::evaluate(b"1 + 2 * 3"), Ok(7));
/// assert!(calc::evaluate(b"(1 + 2").is_err());
/// ```
pub fn evaluate(line: &[u8]) -> Result<i64, EvalError> {
    let mut machine = Machine::default();
    let mut expect_operand = true;
    let mut pos = 0;

    while let Some(&b) = line.get(pos) {
        if is_space(b) {
            pos += 1;
            continue;
        }
        if expect_operand {
            match b {
                b'-' => machine.operators.push(Pending::Neg),
                b'(' => machine.operators.push(Pending::LParen),
                b'0'..=b'9' => {
                    let value = parse_number(line, &mut pos)?;
                    machine.operands.push(value);
                    expect_operand = false;
                    continue;
                }
                _ => return Err(EvalError::Syntax),
            }
        } else if b == b')' {
            machine.reduce_while_binds(0)?;
            if machine.operators.pop() != Some(Pending::LParen) {
                return Err(EvalError::Syntax);
            }
        } else {
            let op = BinOp::from_byte(b).ok_or(EvalError::Syntax)?;
            machine.reduce_while_binds(op.precedence())?;
            machine.operators.push(Pending::Bin(op));
            expect_operand = true;
        }
        pos += 1;
    }

    if expect_operand {
        return Err(EvalError::Syntax);
    }
    while let Some(op) = machine.operators.pop() {
        machine.reduce(op)?;
    }
    match machine.operands.as_slice() {
        &[value] => Ok(value),
        _ => Err(EvalError::Syntax),
    }
}

#[cfg(test)]
mod tests {
    use super::{EvalError, evaluate};

    fn eval(s: &str) -> Result<i64, EvalError> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("\t42 "), Ok(42));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("1 % (2 - 2)"), Err(EvalError::DivisionByZero));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("- - 1"), Ok(1));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(EvalError::Overflow)
        );
        assert_eq!(
            eval("-(-9223372036854775807 - 1)"),
            Err(EvalError::Overflow)
        );
        // Unary minus binds tighter than division.
        assert_eq!(
            eval("-(-9223372036854775807 - 1) / 2"),
            Err(EvalError::Overflow)
        );
        assert_eq!(eval("3037000500 * 3037000500"), Err(EvalError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "(", "1 -", "*1", "1 ** 2",
            "-", "1\r", "",
        ] {
            assert_eq!(eval(s), Err(EvalError::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        let s = format!("{}7", "-".repeat(depth));
        assert_eq!(eval(&s), Ok(7));
    }
}
