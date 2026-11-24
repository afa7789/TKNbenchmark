//! Tokenizer and iterative (shunting-yard) evaluator for integer expressions.
//!
//! The evaluator uses explicit stacks rather than recursion so that deeply
//! nested input (e.g. thousands of parentheses or unary minuses) cannot
//! overflow the call stack.

use std::fmt;

/// Reasons an expression fails to produce a value.
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token {
    Number(i64),
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    LParen,
    RParen,
}

/// Lazily splits a byte line into tokens, skipping spaces and tabs.
struct Lexer<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Lexer<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, pos: 0 }
    }

    fn number(&mut self) -> Result<Token, Error> {
        let mut value: i64 = 0;
        while let Some(&b) = self.input.get(self.pos).filter(|b| b.is_ascii_digit()) {
            value = value
                .checked_mul(10)
                .and_then(|v| v.checked_add(i64::from(b - b'0')))
                .ok_or(Error::Overflow)?;
            self.pos += 1;
        }
        Ok(Token::Number(value))
    }
}

impl Iterator for Lexer<'_> {
    type Item = Result<Token, Error>;

    fn next(&mut self) -> Option<Self::Item> {
        while matches!(self.input.get(self.pos), Some(b' ' | b'\t')) {
            self.pos += 1;
        }
        let &b = self.input.get(self.pos)?;
        if b.is_ascii_digit() {
            return Some(self.number());
        }
        self.pos += 1;
        Some(match b {
            b'+' => Ok(Token::Plus),
            b'-' => Ok(Token::Minus),
            b'*' => Ok(Token::Star),
            b'/' => Ok(Token::Slash),
            b'%' => Ok(Token::Percent),
            b'(' => Ok(Token::LParen),
            b')' => Ok(Token::RParen),
            _ => Err(Error::Syntax),
        })
    }
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
    fn from_token(token: Token) -> Option<Self> {
        Some(match token {
            Token::Plus => Self::Add,
            Token::Minus => Self::Sub,
            Token::Star => Self::Mul,
            Token::Slash => Self::Div,
            Token::Percent => Self::Rem,
            _ => return None,
        })
    }

    fn precedence(self) -> u8 {
        match self {
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> Result<i64, Error> {
        match self {
            Self::Add => lhs.checked_add(rhs).ok_or(Error::Overflow),
            Self::Sub => lhs.checked_sub(rhs).ok_or(Error::Overflow),
            Self::Mul => lhs.checked_mul(rhs).ok_or(Error::Overflow),
            Self::Div if rhs == 0 => Err(Error::DivisionByZero),
            Self::Div => lhs.checked_div(rhs).ok_or(Error::Overflow),
            Self::Rem if rhs == 0 => Err(Error::DivisionByZero),
            // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
            Self::Rem => Ok(lhs.wrapping_rem(rhs)),
        }
    }
}

/// Entries on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Neg,
    Binary(BinOp),
    LParen,
}

/// Operator and operand stacks of the shunting-yard algorithm.
#[derive(Default)]
struct Machine {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Machine {
    fn pop_value(&mut self) -> Result<i64, Error> {
        self.values.pop().ok_or(Error::Syntax)
    }

    /// Applies `op` to the operand stack.
    fn reduce(&mut self, op: StackOp) -> Result<(), Error> {
        let result = match op {
            StackOp::Neg => self.pop_value()?.checked_neg().ok_or(Error::Overflow)?,
            StackOp::Binary(bin) => {
                let rhs = self.pop_value()?;
                let lhs = self.pop_value()?;
                bin.apply(lhs, rhs)?
            }
            StackOp::LParen => return Err(Error::Syntax),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces every pending operator that binds at least as tightly as `incoming`
    /// (left associativity), stopping at an open parenthesis.
    fn push_binary(&mut self, incoming: BinOp) -> Result<(), Error> {
        while let Some(&top) = self.ops.last() {
            let binds_tighter = match top {
                StackOp::Neg => true,
                StackOp::Binary(op) => op.precedence() >= incoming.precedence(),
                StackOp::LParen => false,
            };
            if !binds_tighter {
                break;
            }
            self.ops.pop();
            self.reduce(top)?;
        }
        self.ops.push(StackOp::Binary(incoming));
        Ok(())
    }

    /// Reduces operators back to the matching open parenthesis and discards it.
    fn close_paren(&mut self) -> Result<(), Error> {
        loop {
            match self.ops.pop().ok_or(Error::Syntax)? {
                StackOp::LParen => return Ok(()),
                op => self.reduce(op)?,
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

/// Evaluates a single expression line (without its trailing newline).
pub fn evaluate(line: &[u8]) -> Result<i64, Error> {
    let mut machine = Machine::default();
    // True when the grammar requires an operand next (start of input, after an
    // operator or an open parenthesis); false right after a complete operand.
    let mut expect_operand = true;

    for token in Lexer::new(line) {
        let token = token?;
        if expect_operand {
            match token {
                Token::Number(n) => {
                    machine.values.push(n);
                    expect_operand = false;
                }
                Token::Minus => machine.ops.push(StackOp::Neg),
                Token::LParen => machine.ops.push(StackOp::LParen),
                _ => return Err(Error::Syntax),
            }
        } else if token == Token::RParen {
            machine.close_paren()?;
        } else if let Some(op) = BinOp::from_token(token) {
            machine.push_binary(op)?;
            expect_operand = true;
        } else {
            return Err(Error::Syntax);
        }
    }

    if expect_operand {
        return Err(Error::Syntax);
    }
    machine.finish()
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
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("1 % 0"), Err(Error::DivisionByZero));
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
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 (2)", "(1)(2)", "-", "1 * * 2"] {
            assert_eq!(eval(s), Err(Error::Syntax), "{s}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}7{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(7));
        let s = format!("{}7", "-".repeat(depth + 1));
        assert_eq!(eval(&s), Ok(-7));
    }
}
