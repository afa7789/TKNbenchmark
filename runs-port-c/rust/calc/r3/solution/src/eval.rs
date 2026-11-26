//! Expression evaluation using an explicit-stack operator-precedence
//! algorithm, so arbitrarily deep nesting cannot exhaust the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result does not fit in an `i64`.
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    LParen,
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
}

impl Op {
    fn precedence(self) -> u8 {
        match self {
            Self::LParen => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
            Self::Neg => 3,
        }
    }

    fn binary_from_byte(b: u8) -> Option<Self> {
        Some(match b {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    fn apply_binary(self, a: i64, b: i64) -> Result<i64, EvalError> {
        match self {
            Self::Add => a.checked_add(b).ok_or(EvalError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(EvalError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(EvalError::Overflow),
            Self::Div if b == 0 => Err(EvalError::DivisionByZero),
            Self::Div => a.checked_div(b).ok_or(EvalError::Overflow),
            Self::Rem if b == 0 => Err(EvalError::DivisionByZero),
            // `i64::MIN % -1` is mathematically 0; wrapping_rem yields exactly that.
            Self::Rem => Ok(a.wrapping_rem(b)),
            Self::LParen | Self::Neg => unreachable!("{self:?} is not a binary operator"),
        }
    }
}

/// Returns true for the intra-line whitespace the grammar allows.
pub fn is_blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

/// Reusable evaluator; its stacks are retained between calls to avoid
/// reallocating for every line.
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
    pub fn evaluate(&mut self, expr: &[u8]) -> Result<i64, EvalError> {
        self.values.clear();
        self.ops.clear();

        let mut want_operand = true;
        let mut i = 0;
        while let Some(&c) = expr.get(i) {
            if is_blank(c) {
                i += 1;
                continue;
            }

            if want_operand {
                match c {
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&expr[i..])?;
                        self.values.push(value);
                        i += len;
                        want_operand = false;
                        continue;
                    }
                    b'-' => self.ops.push(Op::Neg),
                    b'(' => self.ops.push(Op::LParen),
                    _ => return Err(EvalError::Syntax),
                }
                i += 1;
                continue;
            }

            if c == b')' {
                loop {
                    match self.ops.last() {
                        None => return Err(EvalError::Syntax),
                        Some(Op::LParen) => break,
                        Some(_) => self.apply_top()?,
                    }
                }
                self.ops.pop();
                i += 1;
                continue;
            }

            let op = Op::binary_from_byte(c).ok_or(EvalError::Syntax)?;
            // All binary operators are left-associative.
            while self
                .ops
                .last()
                .is_some_and(|top| top.precedence() >= op.precedence())
            {
                self.apply_top()?;
            }
            self.ops.push(op);
            want_operand = true;
            i += 1;
        }

        if want_operand {
            return Err(EvalError::Syntax);
        }
        while let Some(&top) = self.ops.last() {
            if top == Op::LParen {
                return Err(EvalError::Syntax);
            }
            self.apply_top()?;
        }
        match self.values.as_slice() {
            &[value] => Ok(value),
            _ => Err(EvalError::Syntax),
        }
    }

    /// Pops the top operator and applies it to the value stack.
    fn apply_top(&mut self) -> Result<(), EvalError> {
        let op = self.ops.pop().ok_or(EvalError::Syntax)?;
        let b = self.values.pop().ok_or(EvalError::Syntax)?;
        let result = if op == Op::Neg {
            b.checked_neg().ok_or(EvalError::Overflow)?
        } else {
            let a = self.values.pop().ok_or(EvalError::Syntax)?;
            op.apply_binary(a, b)?
        };
        self.values.push(result);
        Ok(())
    }
}

/// Parses the leading run of ASCII digits, returning its value and length.
fn parse_number(s: &[u8]) -> Result<(i64, usize), EvalError> {
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

    fn eval(s: &str) -> Result<i64, EvalError> {
        Evaluator::new().evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
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
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "1\r", ")"] {
            assert_eq!(eval(s), Err(EvalError::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let n = 100_000;
        let s = format!("{}1{}", "(".repeat(n), ")".repeat(n));
        assert_eq!(eval(&s), Ok(1));
        let s = format!("{}1", "-".repeat(n));
        assert_eq!(eval(&s), Ok(1));
    }
}
