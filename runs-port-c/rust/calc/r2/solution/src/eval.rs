//! Iterative operator-precedence (shunting-yard) evaluator.
//!
//! Explicit stacks are used instead of recursion so that arbitrarily deep
//! nesting cannot exhaust the call stack.

use std::fmt;

/// Why an expression failed to evaluate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    Syntax,
    DivisionByZero,
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

/// Entries of the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    LParen,
    Neg,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
}

impl Op {
    fn binary(byte: u8) -> Option<Self> {
        Some(match byte {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Mod,
            _ => return None,
        })
    }

    /// Binding strength; `(` never reduces by precedence.
    fn precedence(self) -> u8 {
        match self {
            Self::LParen => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Mod => 2,
            Self::Neg => 3,
        }
    }

    fn apply_binary(self, a: i64, b: i64) -> Result<i64, EvalError> {
        match self {
            Self::Add => a.checked_add(b).ok_or(EvalError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(EvalError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(EvalError::Overflow),
            Self::Div | Self::Mod if b == 0 => Err(EvalError::DivisionByZero),
            Self::Div => a.checked_div(b).ok_or(EvalError::Overflow),
            // `i64::MIN % -1` is mathematically 0; wrapping_rem yields exactly that.
            Self::Mod => Ok(a.wrapping_rem(b)),
            Self::LParen | Self::Neg => unreachable!("{self:?} is not a binary operator"),
        }
    }
}

pub fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

/// Reusable evaluator; keeps its stack allocations between expressions.
#[derive(Debug, Default)]
pub struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    pub fn new() -> Self {
        Self::default()
    }

    /// Evaluates a single expression (without its trailing newline).
    pub fn evaluate(&mut self, line: &[u8]) -> Result<i64, EvalError> {
        self.values.clear();
        self.ops.clear();

        let mut want_operand = true;
        let mut i = 0;

        loop {
            while line.get(i).copied().is_some_and(is_blank) {
                i += 1;
            }
            let Some(&c) = line.get(i) else { break };

            if want_operand {
                match c {
                    b'-' => {
                        self.ops.push(Op::Neg);
                        i += 1;
                    }
                    b'(' => {
                        self.ops.push(Op::LParen);
                        i += 1;
                    }
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&line[i..])?;
                        self.values.push(value);
                        i += len;
                        want_operand = false;
                    }
                    _ => return Err(EvalError::Syntax),
                }
                continue;
            }

            i += 1;
            if c == b')' {
                self.reduce_while(0)?;
                // Anything other than '(' here means the ')' is unmatched.
                if self.ops.pop() != Some(Op::LParen) {
                    return Err(EvalError::Syntax);
                }
            } else {
                let op = Op::binary(c).ok_or(EvalError::Syntax)?;
                self.reduce_while(op.precedence())?;
                self.ops.push(op);
                want_operand = true;
            }
        }

        if want_operand {
            return Err(EvalError::Syntax);
        }
        self.reduce_while(0)?;
        if !self.ops.is_empty() {
            return Err(EvalError::Syntax); // unmatched '('
        }
        debug_assert_eq!(self.values.len(), 1);
        self.values.pop().ok_or(EvalError::Syntax)
    }

    /// Reduces while the top operator binds at least as tightly as `prec`.
    fn reduce_while(&mut self, prec: u8) -> Result<(), EvalError> {
        while let Some(&op) = self.ops.last() {
            if op == Op::LParen || op.precedence() < prec {
                break;
            }
            self.ops.pop();
            self.reduce(op)?;
        }
        Ok(())
    }

    fn reduce(&mut self, op: Op) -> Result<(), EvalError> {
        // The parser guarantees operands are present for every operator.
        if op == Op::Neg {
            let v = self.values.last_mut().expect("operand for unary minus");
            *v = v.checked_neg().ok_or(EvalError::Overflow)?;
        } else {
            let b = self.values.pop().expect("right operand");
            let a = self.values.last_mut().expect("left operand");
            *a = op.apply_binary(*a, b)?;
        }
        Ok(())
    }
}

/// Parses a run of ASCII digits at the start of `digits`, returning the value
/// and the number of bytes consumed.
fn parse_number(digits: &[u8]) -> Result<(i64, usize), EvalError> {
    let len = digits.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = digits[..len].iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)?.checked_add(i64::from(d - b'0'))
    });
    value.map(|v| (v, len)).ok_or(EvalError::Overflow)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, EvalError> {
        Evaluator::new().evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("\t( ( 42 ) )\t"), Ok(42));
    }

    #[test]
    fn limits() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
        assert_eq!(eval("9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("3037000500 * 3037000500"), Err(EvalError::Overflow));
        assert_eq!(eval("000000000000000000000000001"), Ok(1));
    }

    #[test]
    fn errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", ")(", "1 + 2)", "-", "1 ** 2"] {
            assert_eq!(eval(s), Err(EvalError::Syntax), "{s:?}");
        }
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(EvalError::DivisionByZero));
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&"-".repeat(depth + 1).replace("--", "- -")), Err(EvalError::Syntax));
        assert_eq!(eval(&format!("{}7", "-".repeat(depth))), Ok(7));
    }
}
