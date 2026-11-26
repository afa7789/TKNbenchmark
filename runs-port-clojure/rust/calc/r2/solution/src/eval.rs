//! Lexer and recursive-descent evaluator for signed 64-bit integer expressions.
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

use std::fmt;

/// Reasons an expression cannot be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// A byte outside the grammar.
    UnexpectedChar(u8),
    /// An integer literal greater than `i64::MAX`.
    LiteralOutOfRange,
    /// An operand was expected but not found.
    ExpectedOperand,
    /// A `(` without its matching `)`.
    ExpectedCloseParen,
    /// Tokens remain after a complete expression.
    TrailingInput,
    /// Division or remainder by zero.
    DivisionByZero,
    /// An arithmetic result outside the 64-bit range.
    Overflow,
}

impl fmt::Display for EvalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnexpectedChar(c) => write!(f, "unexpected character {:?}", char::from(*c)),
            Self::LiteralOutOfRange => f.write_str("integer literal out of range"),
            Self::ExpectedOperand => f.write_str("expected operand"),
            Self::ExpectedCloseParen => f.write_str("expected )"),
            Self::TrailingInput => f.write_str("unexpected trailing input"),
            Self::DivisionByZero => f.write_str("division by zero"),
            Self::Overflow => f.write_str("overflow"),
        }
    }
}

impl std::error::Error for EvalError {}

pub type Result<T> = std::result::Result<T, EvalError>;

/// Returns true for the inter-token whitespace allowed by the grammar.
pub fn is_blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token {
    Num(i64),
    Op(BinOp),
    LParen,
    RParen,
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
    fn apply(self, a: i64, b: i64) -> Result<i64> {
        match self {
            Self::Add => a.checked_add(b).ok_or(EvalError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(EvalError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(EvalError::Overflow),
            Self::Div if b == 0 => Err(EvalError::DivisionByZero),
            Self::Div => a.checked_div(b).ok_or(EvalError::Overflow),
            Self::Rem if b == 0 => Err(EvalError::DivisionByZero),
            // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

/// Splits a line into tokens, rejecting any byte outside the grammar.
fn tokenize(line: &[u8]) -> Result<Vec<Token>> {
    let mut tokens = Vec::new();
    let mut i = 0;
    while let Some(&c) = line.get(i) {
        i += 1;
        let token = match c {
            b if is_blank(b) => continue,
            b'0'..=b'9' => {
                let start = i - 1;
                while line.get(i).is_some_and(u8::is_ascii_digit) {
                    i += 1;
                }
                Token::Num(parse_literal(&line[start..i])?)
            }
            b'+' => Token::Op(BinOp::Add),
            b'-' => Token::Op(BinOp::Sub),
            b'*' => Token::Op(BinOp::Mul),
            b'/' => Token::Op(BinOp::Div),
            b'%' => Token::Op(BinOp::Rem),
            b'(' => Token::LParen,
            b')' => Token::RParen,
            other => return Err(EvalError::UnexpectedChar(other)),
        };
        tokens.push(token);
    }
    Ok(tokens)
}

/// Parses a run of ASCII digits as a non-negative `i64`.
fn parse_literal(digits: &[u8]) -> Result<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(EvalError::LiteralOutOfRange)
    })
}

/// Recursive-descent parser that evaluates as it parses.
struct Parser<'a> {
    tokens: &'a [Token],
    pos: usize,
}

impl Parser<'_> {
    fn peek(&self) -> Option<Token> {
        self.tokens.get(self.pos).copied()
    }

    fn expr(&mut self) -> Result<i64> {
        self.left_assoc(Self::term, |op| matches!(op, BinOp::Add | BinOp::Sub))
    }

    fn term(&mut self) -> Result<i64> {
        self.left_assoc(Self::unary, |op| {
            matches!(op, BinOp::Mul | BinOp::Div | BinOp::Rem)
        })
    }

    /// Parses a left-associative chain of `operand` joined by operators accepted by `accepts`.
    fn left_assoc(
        &mut self,
        operand: fn(&mut Self) -> Result<i64>,
        accepts: fn(BinOp) -> bool,
    ) -> Result<i64> {
        let mut acc = operand(self)?;
        while let Some(Token::Op(op)) = self.peek() {
            if !accepts(op) {
                break;
            }
            self.pos += 1;
            let rhs = operand(self)?;
            acc = op.apply(acc, rhs)?;
        }
        Ok(acc)
    }

    fn unary(&mut self) -> Result<i64> {
        if self.peek() == Some(Token::Op(BinOp::Sub)) {
            self.pos += 1;
            self.unary()?.checked_neg().ok_or(EvalError::Overflow)
        } else {
            self.primary()
        }
    }

    fn primary(&mut self) -> Result<i64> {
        match self.peek() {
            Some(Token::Num(n)) => {
                self.pos += 1;
                Ok(n)
            }
            Some(Token::LParen) => {
                self.pos += 1;
                let value = self.expr()?;
                if self.peek() != Some(Token::RParen) {
                    return Err(EvalError::ExpectedCloseParen);
                }
                self.pos += 1;
                Ok(value)
            }
            _ => Err(EvalError::ExpectedOperand),
        }
    }
}

/// Evaluates one expression line.
///
/// Recursion depth grows with the nesting of parentheses and unary minus,
/// so callers handling untrusted input should run this on a large stack.
pub fn evaluate(line: &[u8]) -> Result<i64> {
    let tokens = tokenize(line)?;
    let mut parser = Parser {
        tokens: &tokens,
        pos: 0,
    };
    let value = parser.expr()?;
    if parser.pos == tokens.len() {
        Ok(value)
    } else {
        Err(EvalError::TrailingInput)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("\t2*(3+4)*5 "), Ok(70));
    }

    #[test]
    fn division_truncates_toward_zero() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("1 % 0"), Err(EvalError::DivisionByZero));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(EvalError::LiteralOutOfRange));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("3037000500 * 3037000500"), Err(EvalError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1 + * 2", "1\u{0b}"] {
            assert!(eval(s).is_err(), "{s:?} should fail");
        }
    }
}
