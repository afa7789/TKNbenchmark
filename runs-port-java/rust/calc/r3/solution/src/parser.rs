//! Recursive-descent evaluator for signed 64-bit integer expressions.
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! Spaces and tabs are permitted between tokens. All arithmetic is overflow-checked.

use crate::error::CalcError;

/// Maximum nesting of parentheses and unary minus. The evaluator runs on a
/// thread whose stack comfortably accommodates this depth.
pub const MAX_DEPTH: usize = 1 << 22;

/// Evaluates a complete expression given as raw bytes.
pub fn evaluate(src: &[u8]) -> Result<i64, CalcError> {
    let mut parser = Parser { src, pos: 0, depth: 0 };
    let value = parser.expr()?;
    match parser.peek() {
        None => Ok(value),
        Some(_) => Err(parser.syntax_error()),
    }
}

struct Parser<'a> {
    src: &'a [u8],
    pos: usize,
    depth: usize,
}

impl Parser<'_> {
    fn expr(&mut self) -> Result<i64, CalcError> {
        let mut value = self.term()?;
        while let Some(op @ (b'+' | b'-')) = self.peek() {
            self.pos += 1;
            let rhs = self.term()?;
            value = apply(op, value, rhs)?;
        }
        Ok(value)
    }

    fn term(&mut self) -> Result<i64, CalcError> {
        let mut value = self.unary()?;
        while let Some(op @ (b'*' | b'/' | b'%')) = self.peek() {
            self.pos += 1;
            let rhs = self.unary()?;
            value = apply(op, value, rhs)?;
        }
        Ok(value)
    }

    fn unary(&mut self) -> Result<i64, CalcError> {
        if self.peek() == Some(b'-') {
            self.pos += 1;
            let operand = self.nested(Self::unary)?;
            return operand.checked_neg().ok_or(CalcError::Overflow);
        }
        self.primary()
    }

    fn primary(&mut self) -> Result<i64, CalcError> {
        match self.peek() {
            Some(b'(') => {
                self.pos += 1;
                let value = self.nested(Self::expr)?;
                if self.peek() != Some(b')') {
                    return Err(self.syntax_error());
                }
                self.pos += 1;
                Ok(value)
            }
            Some(c) if c.is_ascii_digit() => self.number(),
            _ => Err(self.syntax_error()),
        }
    }

    fn number(&mut self) -> Result<i64, CalcError> {
        let mut value: i64 = 0;
        while let Some(&c) = self.src.get(self.pos).filter(|c| c.is_ascii_digit()) {
            self.pos += 1;
            value = value
                .checked_mul(10)
                .and_then(|v| v.checked_add(i64::from(c - b'0')))
                .ok_or(CalcError::Overflow)?;
        }
        Ok(value)
    }

    /// Runs `f` one nesting level deeper, failing if the depth limit is exceeded.
    fn nested(
        &mut self,
        f: impl FnOnce(&mut Self) -> Result<i64, CalcError>,
    ) -> Result<i64, CalcError> {
        if self.depth >= MAX_DEPTH {
            return Err(CalcError::TooDeep);
        }
        self.depth += 1;
        let result = f(self);
        self.depth -= 1;
        result
    }

    /// Skips blanks and returns the next byte without consuming it.
    fn peek(&mut self) -> Option<u8> {
        while let Some(b' ' | b'\t') = self.src.get(self.pos) {
            self.pos += 1;
        }
        self.src.get(self.pos).copied()
    }

    fn syntax_error(&self) -> CalcError {
        CalcError::Syntax { pos: self.pos }
    }
}

/// Applies a binary operator with exact 64-bit semantics.
fn apply(op: u8, lhs: i64, rhs: i64) -> Result<i64, CalcError> {
    let result = match op {
        b'+' => lhs.checked_add(rhs),
        b'-' => lhs.checked_sub(rhs),
        b'*' => lhs.checked_mul(rhs),
        b'/' | b'%' if rhs == 0 => return Err(CalcError::DivisionByZero),
        b'/' => lhs.checked_div(rhs),
        // i64::MIN % -1 is mathematically 0; wrapping_rem yields exactly that.
        b'%' => Some(lhs.wrapping_rem(rhs)),
        _ => unreachable!("unknown operator {:?}", char::from(op)),
    };
    result.ok_or(CalcError::Overflow)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, CalcError> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("\t2*(3+4)*5 "), Ok(70));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(CalcError::DivisionByZero));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(CalcError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(CalcError::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(CalcError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1\r", "- 1 -", "1 2 3"] {
            assert!(matches!(eval(s), Err(CalcError::Syntax { .. })), "{s:?}");
        }
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("- ( 2 + 3 )"), Ok(-5));
    }
}
