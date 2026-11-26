//! 64-bit signed integer expression evaluator.
//!
//! Parsing uses an explicit operator stack (shunting-yard), so deeply nested
//! input cannot overflow the call stack.

use std::fmt;

/// Any failure while evaluating an expression.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    /// A byte outside the grammar.
    InvalidCharacter(u8),
    /// A token that is valid in general but not at this position.
    UnexpectedToken,
    /// The expression ended where an operand was required.
    MissingOperand,
    /// A `(` or `)` without its partner.
    UnbalancedParenthesis,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the `i64` range.
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidCharacter(b) => write!(f, "invalid character 0x{b:02x}"),
            Self::UnexpectedToken => f.write_str("unexpected token"),
            Self::MissingOperand => f.write_str("missing operand"),
            Self::UnbalancedParenthesis => f.write_str("unbalanced parenthesis"),
            Self::DivisionByZero => f.write_str("division by zero"),
            Self::Overflow => f.write_str("overflow"),
        }
    }
}

impl std::error::Error for CalcError {}

pub type Result<T> = std::result::Result<T, CalcError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinaryOp {
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
        match self {
            Self::Add => a.checked_add(b).ok_or(CalcError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(CalcError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(CalcError::Overflow),
            Self::Div => {
                if b == 0 {
                    return Err(CalcError::DivisionByZero);
                }
                a.checked_div(b).ok_or(CalcError::Overflow)
            }
            Self::Rem => {
                if b == 0 {
                    return Err(CalcError::DivisionByZero);
                }
                // The exact remainder always fits; only `i64::MIN % -1`
                // overflows the machine instruction, and its value is 0.
                Ok(a.wrapping_rem(b))
            }
        }
    }
}

/// Entries of the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Neg,
    LParen,
    Binary(BinaryOp),
}

impl StackOp {
    const NEG_PRECEDENCE: u8 = 3;

    /// Precedence of a reducible operator; `None` for the `(` marker.
    fn precedence(self) -> Option<u8> {
        match self {
            Self::Neg => Some(Self::NEG_PRECEDENCE),
            Self::LParen => None,
            Self::Binary(op) => Some(op.precedence()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Token {
    Number(i64),
    Op(BinaryOp),
    LParen,
    RParen,
}

fn is_blank(b: u8) -> bool {
    matches!(b, b' ' | b'\t')
}

/// Returns `true` if the line holds only spaces and tabs.
pub fn is_blank_line(line: &[u8]) -> bool {
    line.iter().copied().all(is_blank)
}

/// Lexer over a single line; yields tokens or the first lexical error.
struct Tokens<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Tokens<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { input, pos: 0 }
    }

    fn number(&mut self) -> Result<i64> {
        let mut value: i64 = 0;
        while let Some(&b) = self.input.get(self.pos).filter(|b| b.is_ascii_digit()) {
            value = value
                .checked_mul(10)
                .and_then(|v| v.checked_add(i64::from(b - b'0')))
                .ok_or(CalcError::Overflow)?;
            self.pos += 1;
        }
        Ok(value)
    }
}

impl Iterator for Tokens<'_> {
    type Item = Result<Token>;

    fn next(&mut self) -> Option<Self::Item> {
        while self.input.get(self.pos).copied().is_some_and(is_blank) {
            self.pos += 1;
        }
        let &b = self.input.get(self.pos)?;
        if b.is_ascii_digit() {
            return Some(self.number().map(Token::Number));
        }
        self.pos += 1;
        let token = match b {
            b'(' => Token::LParen,
            b')' => Token::RParen,
            _ => match BinaryOp::from_byte(b) {
                Some(op) => Token::Op(op),
                None => return Some(Err(CalcError::InvalidCharacter(b))),
            },
        };
        Some(Ok(token))
    }
}

/// Operand and operator stacks of the shunting-yard evaluator.
#[derive(Default)]
struct Machine {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Machine {
    /// Pops and applies the top operator, which must not be `(`.
    fn reduce(&mut self) -> Result<()> {
        let op = self.ops.pop().expect("reduce called on empty operator stack");
        let b = self.values.pop().expect("operand stack underflow");
        let result = match op {
            StackOp::Neg => b.checked_neg().ok_or(CalcError::Overflow)?,
            StackOp::Binary(op) => {
                let a = self.values.pop().expect("operand stack underflow");
                op.apply(a, b)?
            }
            StackOp::LParen => unreachable!("'(' is never reduced"),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces while the top operator binds at least as tightly as `min`.
    fn reduce_while(&mut self, min: u8) -> Result<()> {
        while self
            .ops
            .last()
            .and_then(|op| op.precedence())
            .is_some_and(|p| p >= min)
        {
            self.reduce()?;
        }
        Ok(())
    }
}

/// Evaluates a single expression.
pub fn evaluate(line: &[u8]) -> Result<i64> {
    let mut m = Machine::default();
    let mut expect_operand = true;

    for token in Tokens::new(line) {
        match (token?, expect_operand) {
            (Token::Number(n), true) => {
                m.values.push(n);
                expect_operand = false;
            }
            (Token::Op(BinaryOp::Sub), true) => m.ops.push(StackOp::Neg),
            (Token::LParen, true) => m.ops.push(StackOp::LParen),
            (Token::Op(op), false) => {
                m.reduce_while(op.precedence())?;
                m.ops.push(StackOp::Binary(op));
                expect_operand = true;
            }
            (Token::RParen, false) => {
                m.reduce_while(0)?;
                if m.ops.pop() != Some(StackOp::LParen) {
                    return Err(CalcError::UnbalancedParenthesis);
                }
            }
            (Token::Number(_) | Token::Op(_) | Token::LParen | Token::RParen, _) => {
                return Err(CalcError::UnexpectedToken);
            }
        }
    }

    if expect_operand {
        return Err(CalcError::MissingOperand);
    }
    m.reduce_while(0)?;
    if !m.ops.is_empty() {
        return Err(CalcError::UnbalancedParenthesis);
    }
    Ok(m.values.pop().expect("a complete expression leaves one value"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Option<i64> {
        evaluate(s.as_bytes()).ok()
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Some(7));
        assert_eq!(eval("(1 + 2) * 3"), Some(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Some(5));
        assert_eq!(eval("10 - 4 - 3"), Some(3));
        assert_eq!(eval("\t2*(3+4)*5 "), Some(70));
    }

    #[test]
    fn division_and_remainder() {
        assert_eq!(eval("-7 / 2"), Some(-3));
        assert_eq!(eval("-7 % 3"), Some(-1));
        assert_eq!(eval("7 % -3"), Some(1));
        assert_eq!(eval("1 / 0"), None);
        assert_eq!(eval("5 % 0"), None);
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Some(5));
        assert_eq!(eval("2 * -3"), Some(-6));
        assert_eq!(eval("1 - -2"), Some(3));
        assert_eq!(eval("-(2 + 3)"), Some(-5));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Some(i64::MAX));
        assert_eq!(eval("9223372036854775808"), None);
        assert_eq!(eval("-9223372036854775808"), None);
        assert_eq!(eval("9223372036854775807 + 1"), None);
        assert_eq!(eval("-9223372036854775807 - 1"), Some(i64::MIN));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), None);
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Some(0));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), None);
        assert_eq!(eval("0000000000000000000000000000042"), Some(42));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "1\r", "(", ")", "1 (2)"] {
            assert_eq!(eval(s), None, "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 200_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Some(1));
        assert_eq!(eval(&"-".repeat(depth + 1)), None);
        assert_eq!(eval(&format!("{}7", "-".repeat(depth))), Some(7));
    }
}
