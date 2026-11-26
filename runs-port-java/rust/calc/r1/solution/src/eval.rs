//! Recursive-descent evaluator for signed 64-bit integer expressions.
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! Any syntax error, division by zero, or overflow makes the whole expression invalid.

use std::fmt;

/// Why an expression has no value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result does not fit in an `i64`.
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

type Result<T> = std::result::Result<T, EvalError>;

/// Evaluates a complete expression; trailing input other than spaces/tabs is a syntax error.
pub fn evaluate(src: &[u8]) -> Result<i64> {
    let mut parser = Parser { src, pos: 0 };
    let value = parser.expr()?;
    match parser.peek() {
        None => Ok(value),
        Some(_) => Err(EvalError::Syntax),
    }
}

/// True if the line holds only spaces and tabs.
pub fn is_blank(line: &[u8]) -> bool {
    line.iter().copied().all(is_space)
}

fn is_space(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

struct Parser<'a> {
    src: &'a [u8],
    pos: usize,
}

impl Parser<'_> {
    /// Skips whitespace and returns the next byte without consuming it.
    fn peek(&mut self) -> Option<u8> {
        while let Some(&b) = self.src.get(self.pos) {
            if !is_space(b) {
                return Some(b);
            }
            self.pos += 1;
        }
        None
    }

    fn expr(&mut self) -> Result<i64> {
        let mut acc = self.term()?;
        loop {
            let op: fn(i64, i64) -> Option<i64> = match self.peek() {
                Some(b'+') => i64::checked_add,
                Some(b'-') => i64::checked_sub,
                _ => return Ok(acc),
            };
            self.pos += 1;
            let rhs = self.term()?;
            acc = op(acc, rhs).ok_or(EvalError::Overflow)?;
        }
    }

    fn term(&mut self) -> Result<i64> {
        let mut acc = self.unary()?;
        loop {
            let op = match self.peek() {
                Some(op @ (b'*' | b'/' | b'%')) => op,
                _ => return Ok(acc),
            };
            self.pos += 1;
            let rhs = self.unary()?;
            acc = match op {
                b'*' => acc.checked_mul(rhs).ok_or(EvalError::Overflow)?,
                _ if rhs == 0 => return Err(EvalError::DivisionByZero),
                b'/' => acc.checked_div(rhs).ok_or(EvalError::Overflow)?,
                // `i64::MIN % -1` is mathematically 0, which is the required result.
                _ => acc.wrapping_rem(rhs),
            };
        }
    }

    fn unary(&mut self) -> Result<i64> {
        if self.peek() == Some(b'-') {
            self.pos += 1;
            return self.unary()?.checked_neg().ok_or(EvalError::Overflow);
        }
        self.primary()
    }

    fn primary(&mut self) -> Result<i64> {
        match self.peek() {
            Some(b'(') => {
                self.pos += 1;
                let value = self.expr()?;
                if self.peek() != Some(b')') {
                    return Err(EvalError::Syntax);
                }
                self.pos += 1;
                Ok(value)
            }
            Some(b'0'..=b'9') => self.number(),
            _ => Err(EvalError::Syntax),
        }
    }

    fn number(&mut self) -> Result<i64> {
        let mut value: i64 = 0;
        while let Some(&b) = self.src.get(self.pos).filter(|b| b.is_ascii_digit()) {
            value = value
                .checked_mul(10)
                .and_then(|v| v.checked_add(i64::from(b - b'0')))
                .ok_or(EvalError::Overflow)?;
            self.pos += 1;
        }
        Ok(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arithmetic() {
        assert_eq!(evaluate(b"1 + 2 * 3"), Ok(7));
        assert_eq!(evaluate(b"-7 / 2"), Ok(-3));
        assert_eq!(evaluate(b"-7 % 3"), Ok(-1));
        assert_eq!(evaluate(b"7 % -3"), Ok(1));
        assert_eq!(evaluate(b"10 - 4 - 3"), Ok(3));
        assert_eq!(evaluate(b"--5"), Ok(5));
        assert_eq!(evaluate(b"(-9223372036854775807 - 1) % -1"), Ok(0));
    }

    #[test]
    fn errors() {
        assert_eq!(evaluate(b"(1 + 2"), Err(EvalError::Syntax));
        assert_eq!(evaluate(b"1 2"), Err(EvalError::Syntax));
        assert_eq!(evaluate(b"+1"), Err(EvalError::Syntax));
        assert_eq!(evaluate(b"1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(evaluate(b"9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(evaluate(b"9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(evaluate(b"(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
        assert_eq!(evaluate(b"-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
    }

    #[test]
    fn blank() {
        assert!(is_blank(b" \t "));
        assert!(is_blank(b""));
        assert!(!is_blank(b" 1 "));
    }
}
