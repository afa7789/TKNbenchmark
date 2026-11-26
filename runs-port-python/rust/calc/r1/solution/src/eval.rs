//! Evaluation of 64-bit signed integer expressions.
//!
//! Grammar (spaces and tabs may separate any two tokens):
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! An operator-precedence (shunting-yard) evaluator is used rather than
//! recursive descent so that deeply nested input cannot overflow the stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result lies outside the `i64` range.
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for CalcError {}

type Result<T> = std::result::Result<T, CalcError>;

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

    fn apply(self, a: i64, b: i64) -> Result<i64> {
        if matches!(self, Self::Div | Self::Rem) && b == 0 {
            return Err(CalcError::DivisionByZero);
        }
        match self {
            Self::Add => a.checked_add(b),
            Self::Sub => a.checked_sub(b),
            Self::Mul => a.checked_mul(b),
            // Rust's `/` truncates toward zero; only `i64::MIN / -1` overflows.
            Self::Div => a.checked_div(b),
            // The remainder always fits: `i64::MIN % -1` is 0.
            Self::Rem => Some(a.wrapping_rem(b)),
        }
        .ok_or(CalcError::Overflow)
    }
}

/// An entry on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Binary(BinOp),
    Negate,
    LParen,
}

impl StackOp {
    /// Binding strength; unary minus binds tighter than every binary operator,
    /// and a parenthesis acts as a barrier.
    fn precedence(self) -> u8 {
        match self {
            Self::Binary(op) => op.precedence(),
            Self::Negate => 3,
            Self::LParen => 0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token {
    Number(i64),
    Op(u8),
}

/// Splits a line into tokens, skipping spaces and tabs.
struct Tokens<'a> {
    rest: &'a [u8],
}

impl Iterator for Tokens<'_> {
    type Item = Result<Token>;

    fn next(&mut self) -> Option<Self::Item> {
        let start = self.rest.iter().position(|&b| b != b' ' && b != b'\t')?;
        self.rest = &self.rest[start..];
        let first = self.rest[0];
        if first.is_ascii_digit() {
            let len = self
                .rest
                .iter()
                .position(|b| !b.is_ascii_digit())
                .unwrap_or(self.rest.len());
            let (digits, rest) = self.rest.split_at(len);
            self.rest = rest;
            return Some(parse_literal(digits).map(Token::Number));
        }
        self.rest = &self.rest[1..];
        Some(match first {
            b'+' | b'-' | b'*' | b'/' | b'%' | b'(' | b')' => Ok(Token::Op(first)),
            _ => Err(CalcError::Syntax),
        })
    }
}

fn parse_literal(digits: &[u8]) -> Result<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })
}

/// Operand and operator stacks of the shunting-yard evaluator.
#[derive(Default)]
struct Machine {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Machine {
    /// Pops the top operator and applies it to the operand stack.
    fn reduce(&mut self) -> Result<()> {
        let op = self.ops.pop().ok_or(CalcError::Syntax)?;
        let mut pop = || self.values.pop().ok_or(CalcError::Syntax);
        let value = match op {
            StackOp::Negate => pop()?.checked_neg().ok_or(CalcError::Overflow)?,
            StackOp::Binary(op) => {
                let b = pop()?;
                let a = pop()?;
                op.apply(a, b)?
            }
            StackOp::LParen => return Err(CalcError::Syntax),
        };
        self.values.push(value);
        Ok(())
    }

    /// Reduces every operator that binds at least as tightly as `prec`.
    fn reduce_while(&mut self, prec: u8) -> Result<()> {
        while self.ops.last().is_some_and(|op| op.precedence() >= prec) {
            self.reduce()?;
        }
        Ok(())
    }
}

/// Evaluates one expression (without its trailing newline).
pub fn evaluate(line: &[u8]) -> Result<i64> {
    let mut m = Machine::default();
    let mut expect_operand = true;

    for token in (Tokens { rest: line }) {
        let token = token?;
        if expect_operand {
            match token {
                Token::Number(n) => {
                    m.values.push(n);
                    expect_operand = false;
                }
                Token::Op(b'-') => m.ops.push(StackOp::Negate),
                Token::Op(b'(') => m.ops.push(StackOp::LParen),
                Token::Op(_) => return Err(CalcError::Syntax),
            }
            continue;
        }
        match token {
            Token::Op(b')') => {
                m.reduce_while(1)?;
                if m.ops.pop() != Some(StackOp::LParen) {
                    return Err(CalcError::Syntax);
                }
            }
            Token::Op(b) => {
                let op = BinOp::from_byte(b).ok_or(CalcError::Syntax)?;
                // Left-associative: reduce operators of equal or higher precedence.
                m.reduce_while(op.precedence())?;
                m.ops.push(StackOp::Binary(op));
                expect_operand = true;
            }
            Token::Number(_) => return Err(CalcError::Syntax),
        }
    }

    if expect_operand {
        return Err(CalcError::Syntax);
    }
    while !m.ops.is_empty() {
        m.reduce()?;
    }
    match m.values[..] {
        [value] => Ok(value),
        _ => Err(CalcError::Syntax),
    }
}

#[cfg(test)]
mod tests {
    use super::{CalcError, evaluate};

    fn eval(s: &str) -> Result<i64, CalcError> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
    }

    #[test]
    fn truncating_division() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(CalcError::DivisionByZero));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("-2 * 3"), Ok(-6));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(CalcError::Overflow)
        );
        assert_eq!(
            eval("-(-9223372036854775807 - 1)"),
            Err(CalcError::Overflow)
        );
        assert_eq!(eval("3037000500 * 3037000500"), Err(CalcError::Overflow));
        assert_eq!(eval("000000000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for s in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 (2)", "-", "1\r",
        ] {
            assert_eq!(eval(s), Err(CalcError::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&"-".repeat(depth + 1)), Err(CalcError::Syntax));
        assert_eq!(eval(&format!("{}1", "-".repeat(depth))), Ok(1));
    }
}
