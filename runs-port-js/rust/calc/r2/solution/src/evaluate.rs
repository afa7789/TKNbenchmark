//! Signed 64-bit integer expression evaluation.
//!
//! Uses an iterative operator-precedence (shunting-yard) parser so that
//! arbitrarily deep nesting cannot exhaust the call stack.

use std::fmt;

/// Every condition that makes a line evaluate to `error`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// A literal or intermediate result outside the `i64` range.
    Overflow,
    /// Division or remainder by zero.
    DivisionByZero,
    /// An operand was expected but something else was found.
    ExpectedOperand,
    /// A character that cannot appear at this position.
    UnexpectedCharacter,
    /// A `(` without `)` or vice versa.
    UnbalancedParenthesis,
    /// The expression ended while an operand was expected.
    MissingOperand,
}

impl fmt::Display for EvalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Overflow => "overflow",
            Self::DivisionByZero => "division by zero",
            Self::ExpectedOperand => "expected operand",
            Self::UnexpectedCharacter => "unexpected character",
            Self::UnbalancedParenthesis => "unbalanced parenthesis",
            Self::MissingOperand => "missing operand",
        })
    }
}

impl std::error::Error for EvalError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinOp {
    fn from_byte(c: u8) -> Option<Self> {
        Some(match c {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    fn apply(self, a: i64, b: i64) -> Result<i64, EvalError> {
        match self {
            Self::Add => a.checked_add(b).ok_or(EvalError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(EvalError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(EvalError::Overflow),
            Self::Div if b == 0 => Err(EvalError::DivisionByZero),
            // Truncates toward zero; only `i64::MIN / -1` overflows.
            Self::Div => a.checked_div(b).ok_or(EvalError::Overflow),
            Self::Rem if b == 0 => Err(EvalError::DivisionByZero),
            // Sign follows the dividend; `i64::MIN % -1` is mathematically 0.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    LParen,
    Negate,
    Binary(BinOp),
}

impl Op {
    fn precedence(self) -> u8 {
        match self {
            Self::LParen => 0,
            Self::Binary(BinOp::Add | BinOp::Sub) => 1,
            Self::Binary(BinOp::Mul | BinOp::Div | BinOp::Rem) => 2,
            Self::Negate => 3,
        }
    }
}

#[derive(Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    fn pop_value(&mut self) -> i64 {
        self.values
            .pop()
            .expect("parser state guarantees an operand is available")
    }

    /// Applies the operator on top of the stack to its operands.
    fn reduce(&mut self, op: Op) -> Result<(), EvalError> {
        let result = match op {
            Op::Negate => self.pop_value().checked_neg().ok_or(EvalError::Overflow)?,
            Op::Binary(bin) => {
                let b = self.pop_value();
                let a = self.pop_value();
                bin.apply(a, b)?
            }
            Op::LParen => unreachable!("parentheses are never reduced"),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces while the top operator binds at least as tightly as `min_precedence`.
    fn reduce_while(&mut self, min_precedence: u8) -> Result<(), EvalError> {
        while let Some(&op) = self.ops.last() {
            if op == Op::LParen || op.precedence() < min_precedence {
                break;
            }
            self.ops.pop();
            self.reduce(op)?;
        }
        Ok(())
    }
}

fn parse_number(digits: &[u8]) -> Result<i64, EvalError> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(EvalError::Overflow)
    })
}

/// Evaluates one expression as signed 64-bit integer arithmetic.
///
/// Returns `Ok(None)` when the line holds only spaces and tabs.
pub fn evaluate(line: &[u8]) -> Result<Option<i64>, EvalError> {
    let mut ev = Evaluator::default();
    let mut expect_operand = true;
    let mut saw_token = false;

    let n = line.len();
    let mut i = 0;
    while i < n {
        let c = line[i];
        if c == b' ' || c == b'\t' {
            i += 1;
            continue;
        }
        saw_token = true;

        if expect_operand {
            match c {
                b'0'..=b'9' => {
                    let start = i;
                    while i < n && line[i].is_ascii_digit() {
                        i += 1;
                    }
                    ev.values.push(parse_number(&line[start..i])?);
                    expect_operand = false;
                    continue;
                }
                b'-' => ev.ops.push(Op::Negate),
                b'(' => ev.ops.push(Op::LParen),
                _ => return Err(EvalError::ExpectedOperand),
            }
        } else if let Some(bin) = BinOp::from_byte(c) {
            // All binary operators are left-associative.
            let op = Op::Binary(bin);
            ev.reduce_while(op.precedence())?;
            ev.ops.push(op);
            expect_operand = true;
        } else if c == b')' {
            ev.reduce_while(0)?;
            if ev.ops.pop() != Some(Op::LParen) {
                return Err(EvalError::UnbalancedParenthesis);
            }
        } else {
            return Err(EvalError::UnexpectedCharacter);
        }
        i += 1;
    }

    if !saw_token {
        return Ok(None);
    }
    if expect_operand {
        return Err(EvalError::MissingOperand);
    }
    while let Some(op) = ev.ops.pop() {
        if op == Op::LParen {
            return Err(EvalError::UnbalancedParenthesis);
        }
        ev.reduce(op)?;
    }
    Ok(Some(ev.pop_value()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<Option<i64>, EvalError> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(Some(7)));
        assert_eq!(eval("(1 + 2) * 3"), Ok(Some(9)));
        assert_eq!(eval("10 - 4 - 3"), Ok(Some(3)));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(Some(5)));
        assert_eq!(eval("--5"), Ok(Some(5)));
        assert_eq!(eval("-(2 + 3)"), Ok(Some(-5)));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(Some(-3)));
        assert_eq!(eval("-7 % 3"), Ok(Some(-1)));
        assert_eq!(eval("7 % -3"), Ok(Some(1)));
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(EvalError::DivisionByZero));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(Some(0)));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
    }

    #[test]
    fn syntax_errors_and_blanks() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1\r"] {
            assert!(eval(s).is_err(), "{s:?}");
        }
        assert_eq!(eval(""), Ok(None));
        assert_eq!(eval(" \t "), Ok(None));
    }

    #[test]
    fn deep_nesting() {
        let depth = 100_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(Some(1)));
    }
}
