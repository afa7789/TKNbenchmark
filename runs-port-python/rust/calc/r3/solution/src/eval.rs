//! Parsing and evaluation of a single 64-bit signed integer expression.
//!
//! Grammar (spaces and tabs may separate any two tokens):
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! An iterative operator-precedence (shunting-yard) parser is used so that
//! deeply nested input cannot overflow the call stack.

use std::fmt;

/// Reasons an expression fails to evaluate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    /// A byte that does not start any valid token in its position.
    UnexpectedToken(u8),
    /// The expression ended where an operand was required.
    MissingOperand,
    /// A `)` without a matching `(`.
    UnbalancedClose,
    /// A `(` without a matching `)`.
    UnbalancedOpen,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the `i64` range.
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnexpectedToken(b) => write!(f, "unexpected byte 0x{b:02x}"),
            Self::MissingOperand => f.write_str("missing operand"),
            Self::UnbalancedClose => f.write_str("unbalanced ')'"),
            Self::UnbalancedOpen => f.write_str("unbalanced '('"),
            Self::DivisionByZero => f.write_str("division by zero"),
            Self::Overflow => f.write_str("overflow"),
        }
    }
}

impl std::error::Error for CalcError {}

type Result<T> = std::result::Result<T, CalcError>;

/// Binary arithmetic operators.
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
                // The truncated remainder is always representable; only
                // `i64::MIN % -1` trips `checked_rem`, and its value is 0.
                Ok(a.wrapping_rem(b))
            }
        }
    }
}

/// Entries on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Binary(BinOp),
    Negate,
    LParen,
}

/// Shunting-yard evaluation state.
#[derive(Debug, Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Evaluator {
    fn pop_value(&mut self) -> i64 {
        self.values
            .pop()
            .expect("parser invariant: operand stack underflow")
    }

    /// Applies the operator on top of the stack to its operands.
    fn reduce_top(&mut self) -> Result<()> {
        let op = self
            .ops
            .pop()
            .expect("parser invariant: operator stack underflow");
        let result = match op {
            StackOp::Negate => {
                let v = self.pop_value();
                v.checked_neg().ok_or(CalcError::Overflow)?
            }
            StackOp::Binary(op) => {
                let b = self.pop_value();
                let a = self.pop_value();
                op.apply(a, b)?
            }
            StackOp::LParen => unreachable!("parser invariant: '(' is never reduced"),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces every pending operator that binds at least as tightly as
    /// `op`, which makes binary operators left-associative.
    fn push_binary(&mut self, op: BinOp) -> Result<()> {
        while let Some(&top) = self.ops.last() {
            let binds_tighter = match top {
                StackOp::Negate => true,
                StackOp::Binary(t) => t.precedence() >= op.precedence(),
                StackOp::LParen => false,
            };
            if !binds_tighter {
                break;
            }
            self.reduce_top()?;
        }
        self.ops.push(StackOp::Binary(op));
        Ok(())
    }

    fn close_paren(&mut self) -> Result<()> {
        loop {
            match self.ops.last() {
                None => return Err(CalcError::UnbalancedClose),
                Some(StackOp::LParen) => {
                    self.ops.pop();
                    return Ok(());
                }
                Some(_) => self.reduce_top()?,
            }
        }
    }

    fn finish(mut self) -> Result<i64> {
        while let Some(&top) = self.ops.last() {
            if top == StackOp::LParen {
                return Err(CalcError::UnbalancedOpen);
            }
            self.reduce_top()?;
        }
        Ok(self.pop_value())
    }
}

/// Parses a run of ASCII digits as a non-negative `i64`.
fn parse_literal(digits: &[u8]) -> Result<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })
}

/// Evaluates one expression given as raw bytes.
pub fn evaluate(line: &[u8]) -> Result<i64> {
    let mut eval = Evaluator::default();
    let mut expect_operand = true;
    let mut i = 0;

    while let Some(&b) = line.get(i) {
        if matches!(b, b' ' | b'\t') {
            i += 1;
            continue;
        }

        if b.is_ascii_digit() {
            if !expect_operand {
                return Err(CalcError::UnexpectedToken(b));
            }
            let len = line[i..].iter().take_while(|c| c.is_ascii_digit()).count();
            eval.values.push(parse_literal(&line[i..i + len])?);
            expect_operand = false;
            i += len;
            continue;
        }

        match (expect_operand, b) {
            (true, b'-') => eval.ops.push(StackOp::Negate),
            (true, b'(') => eval.ops.push(StackOp::LParen),
            (false, b')') => eval.close_paren()?,
            (false, _) => {
                let op = BinOp::from_byte(b).ok_or(CalcError::UnexpectedToken(b))?;
                eval.push_binary(op)?;
                expect_operand = true;
            }
            (true, _) => return Err(CalcError::UnexpectedToken(b)),
        }
        i += 1;
    }

    if expect_operand {
        return Err(CalcError::MissingOperand);
    }
    eval.finish()
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
    }

    #[test]
    fn truncating_division() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("1 % 0"), Err(CalcError::DivisionByZero));
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
        assert_eq!(eval("-9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(CalcError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(CalcError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(CalcError::Overflow));
        assert_eq!(eval("00000000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1 - ", "\u{b2}", "1\r"] {
            assert!(eval(s).is_err(), "{s:?} should fail");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 100_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        let s = format!("{}1", "-".repeat(depth + 1));
        assert_eq!(eval(&s), Ok(-1));
    }
}
