//! Evaluator for signed 64-bit integer arithmetic expressions.
//!
//! Grammar:
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! Parsing is iterative (operator precedence with explicit stacks) so that
//! deeply nested input cannot overflow the call stack.

use std::fmt;

/// Reasons an expression fails to evaluate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// A byte that does not fit the grammar at its position.
    Unexpected(u8),
    /// The input ended while an operand was still expected.
    MissingOperand,
    /// A `(` without a matching `)` or vice versa.
    UnbalancedParenthesis,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the `i64` range.
    Overflow,
}

impl fmt::Display for EvalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unexpected(b) => write!(f, "unexpected byte 0x{b:02x}"),
            Self::MissingOperand => f.write_str("missing operand"),
            Self::UnbalancedParenthesis => f.write_str("unbalanced parenthesis"),
            Self::DivisionByZero => f.write_str("division by zero"),
            Self::Overflow => f.write_str("overflow"),
        }
    }
}

impl std::error::Error for EvalError {}

type Result<T> = std::result::Result<T, EvalError>;

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
            Self::Add => a.checked_add(b).ok_or(EvalError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(EvalError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(EvalError::Overflow),
            Self::Div if b == 0 => Err(EvalError::DivisionByZero),
            // Truncates toward zero; only `MIN / -1` overflows.
            Self::Div => a.checked_div(b).ok_or(EvalError::Overflow),
            Self::Rem if b == 0 => Err(EvalError::DivisionByZero),
            // Sign follows the dividend; `MIN % -1` is mathematically 0.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Binary(BinaryOp),
    Negate,
    Open,
}

impl StackOp {
    /// Binding strength of a reducible operator; `None` for `(`.
    fn precedence(self) -> Option<u8> {
        match self {
            Self::Binary(op) => Some(op.precedence()),
            Self::Negate => Some(3),
            Self::Open => None,
        }
    }
}

#[derive(Debug, Default)]
struct Machine {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Machine {
    fn push_value(&mut self, value: i64) {
        self.values.push(value);
    }

    fn push_open(&mut self) {
        self.ops.push(StackOp::Open);
    }

    fn push_negate(&mut self) {
        self.ops.push(StackOp::Negate);
    }

    /// Reduces pending operators that bind at least as tightly, then pushes `op`.
    fn push_binary(&mut self, op: BinaryOp) -> Result<()> {
        let prec = op.precedence();
        while let Some(top) = self.ops.last().and_then(|top| top.precedence()) {
            if top < prec {
                break;
            }
            self.reduce_top()?;
        }
        self.ops.push(StackOp::Binary(op));
        Ok(())
    }

    /// Reduces up to and including the matching `(`.
    fn close(&mut self) -> Result<()> {
        loop {
            match self.ops.last() {
                None => return Err(EvalError::UnbalancedParenthesis),
                Some(StackOp::Open) => {
                    self.ops.pop();
                    return Ok(());
                }
                Some(_) => self.reduce_top()?,
            }
        }
    }

    fn finish(mut self) -> Result<i64> {
        while let Some(&top) = self.ops.last() {
            if top == StackOp::Open {
                return Err(EvalError::UnbalancedParenthesis);
            }
            self.reduce_top()?;
        }
        match self.values.as_slice() {
            &[result] => Ok(result),
            _ => Err(EvalError::MissingOperand),
        }
    }

    fn pop_value(&mut self) -> Result<i64> {
        self.values.pop().ok_or(EvalError::MissingOperand)
    }

    fn reduce_top(&mut self) -> Result<()> {
        let value = match self.ops.pop() {
            Some(StackOp::Negate) => {
                let a = self.pop_value()?;
                a.checked_neg().ok_or(EvalError::Overflow)?
            }
            Some(StackOp::Binary(op)) => {
                let b = self.pop_value()?;
                let a = self.pop_value()?;
                op.apply(a, b)?
            }
            Some(StackOp::Open) | None => return Err(EvalError::UnbalancedParenthesis),
        };
        self.values.push(value);
        Ok(())
    }
}

fn is_space(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

/// Returns true when the line contains only spaces and tabs.
pub fn is_blank(line: &[u8]) -> bool {
    line.iter().copied().all(is_space)
}

/// Parses a run of ASCII digits, rejecting values above `i64::MAX`.
fn parse_literal(digits: &[u8]) -> Result<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(EvalError::Overflow)
    })
}

/// Evaluates one expression.
pub fn evaluate(source: &[u8]) -> Result<i64> {
    let mut machine = Machine::default();
    // true: the next token must start an operand; false: an operator or `)`.
    let mut expect_operand = true;
    let mut i = 0;

    while let Some(&c) = source.get(i) {
        if is_space(c) {
            i += 1;
            continue;
        }

        if c.is_ascii_digit() {
            if !expect_operand {
                return Err(EvalError::Unexpected(c));
            }
            let len = source[i..].iter().take_while(|b| b.is_ascii_digit()).count();
            machine.push_value(parse_literal(&source[i..i + len])?);
            i += len;
            expect_operand = false;
            continue;
        }

        i += 1;
        if expect_operand {
            match c {
                b'-' => machine.push_negate(),
                b'(' => machine.push_open(),
                _ => return Err(EvalError::Unexpected(c)),
            }
        } else if let Some(op) = BinaryOp::from_byte(c) {
            machine.push_binary(op)?;
            expect_operand = true;
        } else if c == b')' {
            machine.close()?;
        } else {
            return Err(EvalError::Unexpected(c));
        }
    }

    if expect_operand {
        return Err(EvalError::MissingOperand);
    }
    machine.finish()
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
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("2*(3+4)*5"), Ok(70));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "", "1\r", "- "] {
            assert!(eval(s).is_err(), "{s:?} should fail");
        }
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
    }

    #[test]
    fn deep_nesting() {
        let depth = 100_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&"-".repeat(depth + 1)), Err(EvalError::MissingOperand));
    }
}
