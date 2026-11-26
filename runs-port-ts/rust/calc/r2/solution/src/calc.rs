//! Signed 64-bit integer expression evaluator.
//!
//! Grammar:
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! Parsing is iterative (operator precedence with explicit stacks) so that
//! deeply nested input cannot exhaust the call stack.

use std::fmt;

/// Any syntax, domain, or overflow error.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    UnexpectedByte(u8),
    UnexpectedNumber,
    UnmatchedClose,
    UnmatchedOpen,
    MissingOperand,
    DivisionByZero,
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnexpectedByte(b) => write!(f, "unexpected byte 0x{b:02x}"),
            Self::UnexpectedNumber => f.write_str("unexpected number"),
            Self::UnmatchedClose => f.write_str("unmatched ')'"),
            Self::UnmatchedOpen => f.write_str("unmatched '('"),
            Self::MissingOperand => f.write_str("missing operand"),
            Self::DivisionByZero => f.write_str("division by zero"),
            Self::Overflow => f.write_str("overflow"),
        }
    }
}

impl std::error::Error for CalcError {}

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
        match b {
            b'+' => Some(Self::Add),
            b'-' => Some(Self::Sub),
            b'*' => Some(Self::Mul),
            b'/' => Some(Self::Div),
            b'%' => Some(Self::Rem),
            _ => None,
        }
    }

    fn precedence(self) -> u8 {
        match self {
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, a: i64, b: i64) -> Result<i64, CalcError> {
        match self {
            Self::Add => a.checked_add(b).ok_or(CalcError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(CalcError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(CalcError::Overflow),
            Self::Div if b == 0 => Err(CalcError::DivisionByZero),
            // Truncates toward zero; only `MIN / -1` overflows.
            Self::Div => a.checked_div(b).ok_or(CalcError::Overflow),
            Self::Rem if b == 0 => Err(CalcError::DivisionByZero),
            // Sign follows the dividend; `MIN % -1` is exactly 0, never an error.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Binary(BinaryOp),
    Neg,
    Open,
}

/// Shunting-yard evaluator state for a single expression.
#[derive(Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Evaluator {
    fn pop_value(&mut self) -> i64 {
        self.values
            .pop()
            .expect("operator stack is only reduced when its operands are present")
    }

    /// Pops the top operator and applies it to the value stack.
    fn reduce_top(&mut self) -> Result<(), CalcError> {
        match self.ops.pop() {
            Some(StackOp::Neg) => {
                let v = self.pop_value();
                self.values.push(v.checked_neg().ok_or(CalcError::Overflow)?);
            }
            Some(StackOp::Binary(op)) => {
                let b = self.pop_value();
                let a = self.pop_value();
                self.values.push(op.apply(a, b)?);
            }
            Some(StackOp::Open) | None => {}
        }
        Ok(())
    }

    fn push_binary(&mut self, op: BinaryOp) -> Result<(), CalcError> {
        let prec = op.precedence();
        while let Some(&top) = self.ops.last() {
            match top {
                StackOp::Open => break,
                StackOp::Binary(t) if t.precedence() < prec => break,
                StackOp::Binary(_) | StackOp::Neg => self.reduce_top()?,
            }
        }
        self.ops.push(StackOp::Binary(op));
        Ok(())
    }

    fn close_paren(&mut self) -> Result<(), CalcError> {
        loop {
            match self.ops.last() {
                None => return Err(CalcError::UnmatchedClose),
                Some(StackOp::Open) => {
                    self.ops.pop();
                    return Ok(());
                }
                Some(_) => self.reduce_top()?,
            }
        }
    }

    fn finish(mut self) -> Result<i64, CalcError> {
        while let Some(&top) = self.ops.last() {
            if top == StackOp::Open {
                return Err(CalcError::UnmatchedOpen);
            }
            self.reduce_top()?;
        }
        Ok(self.pop_value())
    }
}

fn is_blank_byte(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

/// Parses a run of ASCII digits as a non-negative `i64`.
fn parse_number(digits: &[u8]) -> Result<i64, CalcError> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })
}

/// Evaluates one expression.
pub fn evaluate(src: &[u8]) -> Result<i64, CalcError> {
    let mut ev = Evaluator::default();
    let mut expect_operand = true;
    let mut i = 0;

    while i < src.len() {
        let b = src[i];
        if is_blank_byte(b) {
            i += 1;
            continue;
        }

        if b.is_ascii_digit() {
            if !expect_operand {
                return Err(CalcError::UnexpectedNumber);
            }
            let start = i;
            while i < src.len() && src[i].is_ascii_digit() {
                i += 1;
            }
            ev.values.push(parse_number(&src[start..i])?);
            expect_operand = false;
            continue;
        }

        i += 1;

        if expect_operand {
            match b {
                b'-' => ev.ops.push(StackOp::Neg),
                b'(' => ev.ops.push(StackOp::Open),
                _ => return Err(CalcError::UnexpectedByte(b)),
            }
            continue;
        }

        if let Some(op) = BinaryOp::from_byte(b) {
            ev.push_binary(op)?;
            expect_operand = true;
        } else if b == b')' {
            ev.close_paren()?;
        } else {
            return Err(CalcError::UnexpectedByte(b));
        }
    }

    if expect_operand {
        return Err(CalcError::MissingOperand);
    }
    ev.finish()
}

/// Returns true if the line contains only spaces and tabs.
pub fn is_blank(line: &[u8]) -> bool {
    line.iter().copied().all(is_blank_byte)
}

/// Produces the output for one input line, or `None` if nothing is printed.
pub fn evaluate_line(line: &[u8]) -> Option<Result<i64, CalcError>> {
    (!is_blank(line)).then(|| evaluate(line))
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
        assert_eq!(eval("--5"), Some(5));
        assert_eq!(eval("-(2 + 3)"), Some(-5));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Some(-3));
        assert_eq!(eval("-7 % 3"), Some(-1));
        assert_eq!(eval("7 % -3"), Some(1));
        assert_eq!(eval("1 / 0"), None);
        assert_eq!(eval("5 % 0"), None);
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Some(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), None);
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Some(i64::MAX));
        assert_eq!(eval("9223372036854775808"), None);
        assert_eq!(eval("-9223372036854775808"), None);
        assert_eq!(eval("9223372036854775807 + 1"), None);
        assert_eq!(eval("-(-9223372036854775807 - 1)"), None);
        assert_eq!(eval("000000000000000000000000001"), Some(1));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "1\r", ")("] {
            assert_eq!(eval(s), None, "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let n = 1_000_000;
        let s = format!("{}1{}", "(".repeat(n), ")".repeat(n));
        assert_eq!(eval(&s), Some(1));
        let s = format!("{}1", "-".repeat(n + 1));
        assert_eq!(eval(&s), Some(-1));
    }
}
