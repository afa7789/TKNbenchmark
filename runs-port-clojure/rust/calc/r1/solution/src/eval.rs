//! Lexing and evaluation of 64-bit signed integer expressions.
//!
//! Grammar (blanks — spaces and tabs — may appear between any two tokens):
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! Evaluation uses operator-precedence parsing with explicit stacks rather
//! than recursion, so arbitrarily deep nesting cannot exhaust the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// Input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result lies outside the `i64` range.
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

/// Binary operators.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinOp {
    fn precedence(self) -> u8 {
        match self {
            BinOp::Add | BinOp::Sub => 1,
            BinOp::Mul | BinOp::Div | BinOp::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> Result<i64> {
        match self {
            BinOp::Add => lhs.checked_add(rhs).ok_or(Error::Overflow),
            BinOp::Sub => lhs.checked_sub(rhs).ok_or(Error::Overflow),
            BinOp::Mul => lhs.checked_mul(rhs).ok_or(Error::Overflow),
            BinOp::Div => match rhs {
                0 => Err(Error::DivisionByZero),
                _ => lhs.checked_div(rhs).ok_or(Error::Overflow),
            },
            // `i64::MIN % -1` is mathematically 0, which `wrapping_rem` yields.
            BinOp::Rem => match rhs {
                0 => Err(Error::DivisionByZero),
                _ => Ok(lhs.wrapping_rem(rhs)),
            },
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token {
    Number(i64),
    Minus,
    Op(BinOp),
    LParen,
    RParen,
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

/// Returns true if the line holds nothing but spaces and tabs.
pub fn is_blank_line(line: &[u8]) -> bool {
    line.iter().copied().all(is_blank)
}

/// Iterator over the tokens of a line; yields `Err` on an invalid character
/// or an out-of-range literal.
struct Lexer<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Lexer<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, pos: 0 }
    }

    fn number(&mut self) -> Result<i64> {
        let mut value: i64 = 0;
        while let Some(&byte) = self.input.get(self.pos) {
            if !byte.is_ascii_digit() {
                break;
            }
            self.pos += 1;
            value = value
                .checked_mul(10)
                .and_then(|v| v.checked_add(i64::from(byte - b'0')))
                .ok_or(Error::Overflow)?;
        }
        Ok(value)
    }
}

impl Iterator for Lexer<'_> {
    type Item = Result<Token>;

    fn next(&mut self) -> Option<Self::Item> {
        while self.input.get(self.pos).copied().is_some_and(is_blank) {
            self.pos += 1;
        }
        let byte = *self.input.get(self.pos)?;
        if byte.is_ascii_digit() {
            return Some(self.number().map(Token::Number));
        }
        self.pos += 1;
        let token = match byte {
            b'+' => Token::Op(BinOp::Add),
            b'-' => Token::Minus,
            b'*' => Token::Op(BinOp::Mul),
            b'/' => Token::Op(BinOp::Div),
            b'%' => Token::Op(BinOp::Rem),
            b'(' => Token::LParen,
            b')' => Token::RParen,
            _ => return Some(Err(Error::Syntax)),
        };
        Some(Ok(token))
    }
}

/// Entries on the pending-operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pending {
    Negate,
    Binary(BinOp),
    Group,
}

/// Operator-precedence evaluator state.
#[derive(Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Pending>,
}

impl Evaluator {
    fn pop_value(&mut self) -> i64 {
        self.values
            .pop()
            .expect("operator stack is only reduced with operands available")
    }

    /// Applies the top pending operator, which must not be a group marker.
    fn reduce_one(&mut self, op: Pending) -> Result<()> {
        let result = match op {
            Pending::Negate => self.pop_value().checked_neg().ok_or(Error::Overflow)?,
            Pending::Binary(op) => {
                let rhs = self.pop_value();
                let lhs = self.pop_value();
                op.apply(lhs, rhs)?
            }
            Pending::Group => unreachable!("group markers are never reduced"),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces pending operators that bind at least as tightly as `min_prec`
    /// (unary minus binds tighter than every binary operator), stopping at a
    /// group marker.
    fn reduce_while(&mut self, min_prec: u8) -> Result<()> {
        while let Some(&op) = self.ops.last() {
            let binds = match op {
                Pending::Negate => true,
                Pending::Binary(b) => b.precedence() >= min_prec,
                Pending::Group => false,
            };
            if !binds {
                break;
            }
            self.ops.pop();
            self.reduce_one(op)?;
        }
        Ok(())
    }

    fn run(mut self, tokens: impl Iterator<Item = Result<Token>>) -> Result<i64> {
        // `expect_operand` is true at the start of a `unary` production.
        let mut expect_operand = true;
        for token in tokens {
            let token = token?;
            if expect_operand {
                match token {
                    Token::Number(n) => {
                        self.values.push(n);
                        expect_operand = false;
                    }
                    Token::Minus => self.ops.push(Pending::Negate),
                    Token::LParen => self.ops.push(Pending::Group),
                    Token::Op(_) | Token::RParen => return Err(Error::Syntax),
                }
            } else {
                match token {
                    Token::Minus => self.push_binary(BinOp::Sub)?,
                    Token::Op(op) => self.push_binary(op)?,
                    Token::RParen => {
                        self.reduce_while(0)?;
                        match self.ops.pop() {
                            Some(Pending::Group) => {}
                            _ => return Err(Error::Syntax),
                        }
                        continue;
                    }
                    Token::Number(_) | Token::LParen => return Err(Error::Syntax),
                }
                expect_operand = true;
            }
        }
        if expect_operand {
            return Err(Error::Syntax);
        }
        self.reduce_while(0)?;
        if !self.ops.is_empty() {
            return Err(Error::Syntax);
        }
        Ok(self.pop_value())
    }

    fn push_binary(&mut self, op: BinOp) -> Result<()> {
        self.reduce_while(op.precedence())?;
        self.ops.push(Pending::Binary(op));
        Ok(())
    }
}

/// Evaluates one expression.
pub fn evaluate(line: &[u8]) -> Result<i64> {
    Evaluator::default().run(Lexer::new(line))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64> {
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
        assert_eq!(eval("- 7 % 3"), Ok(-1));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(Error::Overflow));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("3037000500 * 3037000500"), Err(Error::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1\r", "2 (3)", "-"] {
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
