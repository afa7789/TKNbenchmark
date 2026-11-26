//! Lexer and evaluator for signed 64-bit integer expressions.
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! The evaluator is an iterative operator-precedence parser that keeps one
//! [`Frame`] per open parenthesis on an explicit stack, so arbitrarily deep
//! nesting cannot overflow the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result is outside the 64-bit range.
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

/// Binary operators, grouped by precedence level.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AddOp {
    Add,
    Sub,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MulOp {
    Mul,
    Div,
    Rem,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token {
    Number(i64),
    Add(AddOp),
    Mul(MulOp),
    Open,
    Close,
}

/// Splits a line into tokens, skipping spaces and tabs.
struct Lexer<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Lexer<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, pos: 0 }
    }

    /// Parses the run of ASCII digits starting at the current position.
    fn number(&mut self) -> Result<i64> {
        let mut value: i64 = 0;
        while let Some(&b) = self.input.get(self.pos).filter(|b| b.is_ascii_digit()) {
            value = value
                .checked_mul(10)
                .and_then(|v| v.checked_add(i64::from(b - b'0')))
                .ok_or(Error::Overflow)?;
            self.pos += 1;
        }
        Ok(value)
    }
}

impl Iterator for Lexer<'_> {
    type Item = Result<Token>;

    fn next(&mut self) -> Option<Self::Item> {
        while let Some(&b) = self.input.get(self.pos) {
            let token = match b {
                b' ' | b'\t' => {
                    self.pos += 1;
                    continue;
                }
                b'0'..=b'9' => return Some(self.number().map(Token::Number)),
                b'+' => Token::Add(AddOp::Add),
                b'-' => Token::Add(AddOp::Sub),
                b'*' => Token::Mul(MulOp::Mul),
                b'/' => Token::Mul(MulOp::Div),
                b'%' => Token::Mul(MulOp::Rem),
                b'(' => Token::Open,
                b')' => Token::Close,
                _ => return Some(Err(Error::Syntax)),
            };
            self.pos += 1;
            return Some(Ok(token));
        }
        None
    }
}

impl AddOp {
    fn apply(self, a: i64, b: i64) -> Result<i64> {
        match self {
            AddOp::Add => a.checked_add(b),
            AddOp::Sub => a.checked_sub(b),
        }
        .ok_or(Error::Overflow)
    }
}

impl MulOp {
    fn apply(self, a: i64, b: i64) -> Result<i64> {
        match self {
            MulOp::Mul => a.checked_mul(b).ok_or(Error::Overflow),
            _ if b == 0 => Err(Error::DivisionByZero),
            // `i64::MIN / -1` is the only remaining failure.
            MulOp::Div => a.checked_div(b).ok_or(Error::Overflow),
            // `i64::MIN % -1` is mathematically 0, which `wrapping_rem` yields.
            MulOp::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

/// Applies `count` unary minus signs to `value`.
fn negate(value: i64, count: usize) -> Result<i64> {
    match count {
        0 => Ok(value),
        // The first negation of `i64::MIN` already overflows.
        _ if value == i64::MIN => Err(Error::Overflow),
        _ if count % 2 == 1 => Ok(-value),
        _ => Ok(value),
    }
}

/// Evaluation state for one parenthesised sub-expression (or the whole line).
#[derive(Debug, Default)]
struct Frame {
    /// Value of the terms already folded into the sum, and the operator that
    /// joins it to the term in progress.
    sum: Option<(i64, AddOp)>,
    /// Value of the factors already folded into the term in progress, and the
    /// operator that joins it to the next operand.
    product: Option<(i64, MulOp)>,
    /// Unary minus signs seen before the next operand.
    negations: usize,
    /// The term in progress once an operand has been read for it.
    term: Option<i64>,
}

impl Frame {
    /// Folds a complete operand (after its unary minus signs) into the term.
    fn push_operand(&mut self, operand: i64) -> Result<()> {
        let operand = negate(operand, std::mem::take(&mut self.negations))?;
        let term = match self.product.take() {
            Some((acc, op)) => op.apply(acc, operand)?,
            None => operand,
        };
        self.term = Some(term);
        Ok(())
    }

    /// Takes the finished term, or fails if the operand is missing.
    fn take_term(&mut self) -> Result<i64> {
        self.term.take().ok_or(Error::Syntax)
    }

    fn push_mul(&mut self, op: MulOp) -> Result<()> {
        self.product = Some((self.take_term()?, op));
        Ok(())
    }

    fn push_add(&mut self, op: AddOp) -> Result<()> {
        let value = self.finish()?;
        self.sum = Some((value, op));
        Ok(())
    }

    /// Completes the expression and returns its value.
    fn finish(&mut self) -> Result<i64> {
        let term = self.take_term()?;
        match self.sum.take() {
            Some((acc, op)) => op.apply(acc, term),
            None => Ok(term),
        }
    }
}

/// Evaluates one expression line.
pub fn evaluate(line: &[u8]) -> Result<i64> {
    let mut stack: Vec<Frame> = Vec::new();
    let mut frame = Frame::default();

    for token in Lexer::new(line) {
        // An operand has been read exactly when the frame holds a term;
        // otherwise the parser is waiting for one.
        let expecting_operand = frame.term.is_none();
        match token? {
            Token::Number(n) if expecting_operand => frame.push_operand(n)?,
            Token::Add(AddOp::Sub) if expecting_operand => frame.negations += 1,
            Token::Open if expecting_operand => stack.push(std::mem::take(&mut frame)),
            Token::Add(op) if !expecting_operand => frame.push_add(op)?,
            Token::Mul(op) if !expecting_operand => frame.push_mul(op)?,
            Token::Close if !expecting_operand => {
                let value = frame.finish()?;
                frame = stack.pop().ok_or(Error::Syntax)?;
                frame.push_operand(value)?;
            }
            _ => return Err(Error::Syntax),
        }
    }

    if !stack.is_empty() {
        return Err(Error::Syntax);
    }
    frame.finish()
}

#[cfg(test)]
mod tests {
    use super::{Error, evaluate};

    fn eval(s: &str) -> Result<i64, Error> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("2*(3+4)*5"), Ok(70));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("2 * 3 % 4"), Ok(2));
    }

    #[test]
    fn division_truncates_toward_zero() {
        assert_eq!(eval("7 / 2"), Ok(3));
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(Error::DivisionByZero));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("- - - 4"), Ok(-4));
        assert_eq!(eval("-2 * 3"), Ok(-6));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(Error::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("--(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("3037000500 * 3037000500"), Err(Error::Overflow));
        assert_eq!(eval("00000000000000000000000000042"), Ok(42));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 * * 2", "-", "1 -", "(", "1\r", "2(3)", "(1)(2)", "1 - - "] {
            assert_eq!(eval(s), Err(Error::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}7{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(7));
        let s = format!("{}7", "-".repeat(depth + 1));
        assert_eq!(eval(&s), Ok(-7));
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth - 1));
        assert_eq!(eval(&s), Err(Error::Syntax));
    }
}
