//! Iterative operator-precedence (shunting-yard) evaluator.
//!
//! Operator and value stacks live on the heap, so arbitrarily deep nesting
//! cannot exhaust the call stack.

use std::fmt;

/// Why an expression failed to evaluate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result is outside the `i64` range.
    Overflow,
}

impl fmt::Display for EvalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for EvalError {}

pub type Result<T> = std::result::Result<T, EvalError>;

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
            Self::Add => a.checked_add(b).ok_or(EvalError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(EvalError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(EvalError::Overflow),
            Self::Div if b == 0 => Err(EvalError::DivisionByZero),
            Self::Div => a.checked_div(b).ok_or(EvalError::Overflow),
            Self::Rem if b == 0 => Err(EvalError::DivisionByZero),
            // `i64::MIN % -1` is mathematically 0; wrapping_rem yields exactly that.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Binary(BinOp),
    Neg,
    LParen,
}

impl Op {
    /// Binding strength; `(` is never popped by precedence.
    fn precedence(self) -> u8 {
        match self {
            Self::Binary(op) => op.precedence(),
            Self::Neg => 3,
            Self::LParen => 0,
        }
    }
}

pub fn is_blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

/// Reusable evaluator; keeps its stacks between calls to avoid reallocation.
#[derive(Debug, Default)]
pub struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Evaluates a single expression.
    pub fn evaluate(&mut self, line: &[u8]) -> Result<i64> {
        self.values.clear();
        self.ops.clear();

        let mut expect_operand = true;
        let mut i = 0;

        loop {
            while line.get(i).copied().is_some_and(is_blank) {
                i += 1;
            }
            let Some(&c) = line.get(i) else { break };

            if expect_operand {
                match c {
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&line[i..])?;
                        self.values.push(value);
                        i += len;
                        expect_operand = false;
                    }
                    b'-' => {
                        self.ops.push(Op::Neg);
                        i += 1;
                    }
                    b'(' => {
                        self.ops.push(Op::LParen);
                        i += 1;
                    }
                    _ => return Err(EvalError::Syntax),
                }
            } else {
                if c == b')' {
                    self.reduce(0)?;
                    if self.ops.pop() != Some(Op::LParen) {
                        return Err(EvalError::Syntax);
                    }
                } else {
                    let op = BinOp::from_byte(c).ok_or(EvalError::Syntax)?;
                    self.reduce(op.precedence())?;
                    self.ops.push(Op::Binary(op));
                    expect_operand = true;
                }
                i += 1;
            }
        }

        if expect_operand {
            return Err(EvalError::Syntax);
        }
        self.reduce(0)?;
        match (self.ops.as_slice(), self.values.as_slice()) {
            ([], &[value]) => Ok(value),
            _ => Err(EvalError::Syntax),
        }
    }

    /// Pops and applies operators with precedence at least `min_prec`,
    /// stopping at an open parenthesis.
    fn reduce(&mut self, min_prec: u8) -> Result<()> {
        while let Some(&top) = self.ops.last() {
            if top == Op::LParen || top.precedence() < min_prec {
                break;
            }
            self.ops.pop();
            self.apply(top)?;
        }
        Ok(())
    }

    fn apply(&mut self, op: Op) -> Result<()> {
        match op {
            Op::Neg => {
                let a = self.values.last_mut().ok_or(EvalError::Syntax)?;
                *a = a.checked_neg().ok_or(EvalError::Overflow)?;
            }
            Op::Binary(bin) => {
                let b = self.values.pop().ok_or(EvalError::Syntax)?;
                let a = self.values.last_mut().ok_or(EvalError::Syntax)?;
                *a = bin.apply(*a, b)?;
            }
            Op::LParen => return Err(EvalError::Syntax),
        }
        Ok(())
    }
}

/// Parses the leading run of ASCII digits; returns the value and digit count.
fn parse_number(s: &[u8]) -> Result<(i64, usize)> {
    let len = s.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = s[..len].iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(EvalError::Overflow)
    })?;
    Ok((value, len))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64> {
        Evaluator::new().evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("2 * -3"), Ok(-6));
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
        assert_eq!(eval("3037000500 * 3037000500"), Err(EvalError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "(1))", "1 + 2\r", ")"] {
            assert_eq!(eval(s), Err(EvalError::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&format!("{}1", "-".repeat(depth))), Ok(1));
    }
}
