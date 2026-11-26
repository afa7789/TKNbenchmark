//! Checked 64-bit integer expression evaluation.
//!
//! The evaluator is an operator-precedence (shunting-yard) parser with
//! explicit stacks, so deeply nested input cannot overflow the call stack.

use std::fmt;

/// Every condition that makes a line evaluate to `error`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    /// A character outside the grammar or a token in the wrong place.
    Syntax,
    /// Unmatched `(` or `)`.
    Unbalanced,
    /// The expression ended where an operand was expected.
    MissingOperand,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the `i64` range.
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::Unbalanced => "unbalanced parentheses",
            Self::MissingOperand => "missing operand",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
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
        Some(match b {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    fn apply(self, a: i64, b: i64) -> Result<i64, CalcError> {
        match self {
            Self::Add => a.checked_add(b).ok_or(CalcError::Overflow),
            Self::Sub => a.checked_sub(b).ok_or(CalcError::Overflow),
            Self::Mul => a.checked_mul(b).ok_or(CalcError::Overflow),
            Self::Div if b == 0 => Err(CalcError::DivisionByZero),
            // Truncates toward zero; only `i64::MIN / -1` overflows.
            Self::Div => a.checked_div(b).ok_or(CalcError::Overflow),
            Self::Rem if b == 0 => Err(CalcError::DivisionByZero),
            // Sign follows the dividend. `i64::MIN % -1` is mathematically 0,
            // which `wrapping_rem` yields instead of reporting overflow.
            Self::Rem => Ok(a.wrapping_rem(b)),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Open,
    Neg,
    Binary(BinaryOp),
}

impl StackOp {
    fn precedence(self) -> u8 {
        match self {
            Self::Open => 0,
            Self::Binary(BinaryOp::Add | BinaryOp::Sub) => 1,
            Self::Binary(BinaryOp::Mul | BinaryOp::Div | BinaryOp::Rem) => 2,
            Self::Neg => 3,
        }
    }
}

/// Returns `true` for the inter-token whitespace the grammar allows.
pub fn is_blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

/// Parses a run of ASCII digits, rejecting values above `i64::MAX`.
fn parse_literal(digits: &[u8]) -> Result<i64, CalcError> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })
}

struct Evaluator {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Evaluator {
    fn pop_value(&mut self) -> i64 {
        self.values
            .pop()
            .expect("operator applied with too few operands")
    }

    /// Applies the operator on top of the stack to its operands.
    fn reduce_top(&mut self) -> Result<(), CalcError> {
        let value = match self.ops.pop() {
            Some(StackOp::Neg) => self
                .pop_value()
                .checked_neg()
                .ok_or(CalcError::Overflow)?,
            Some(StackOp::Binary(op)) => {
                let b = self.pop_value();
                let a = self.pop_value();
                op.apply(a, b)?
            }
            Some(StackOp::Open) | None => unreachable!("reduce_top called without an operator"),
        };
        self.values.push(value);
        Ok(())
    }

    /// Reduces every stacked operator binding at least as tightly as `prec`.
    fn reduce_while(&mut self, prec: u8) -> Result<(), CalcError> {
        while let Some(&top) = self.ops.last() {
            if top == StackOp::Open || top.precedence() < prec {
                break;
            }
            self.reduce_top()?;
        }
        Ok(())
    }
}

/// Evaluates one expression line.
pub fn evaluate(line: &[u8]) -> Result<i64, CalcError> {
    let mut ev = Evaluator {
        values: Vec::new(),
        ops: Vec::new(),
    };
    let mut expect_operand = true;
    let mut i = 0;

    while i < line.len() {
        let c = line[i];
        if is_blank(c) {
            i += 1;
            continue;
        }

        if expect_operand {
            match c {
                b'0'..=b'9' => {
                    let len = line[i..].iter().take_while(|b| b.is_ascii_digit()).count();
                    ev.values.push(parse_literal(&line[i..i + len])?);
                    i += len;
                    expect_operand = false;
                    continue;
                }
                b'-' => ev.ops.push(StackOp::Neg),
                b'(' => ev.ops.push(StackOp::Open),
                _ => return Err(CalcError::Syntax),
            }
        } else if c == b')' {
            ev.reduce_while(0)?;
            match ev.ops.pop() {
                Some(StackOp::Open) => {}
                _ => return Err(CalcError::Unbalanced),
            }
        } else if let Some(op) = BinaryOp::from_byte(c) {
            let op = StackOp::Binary(op);
            ev.reduce_while(op.precedence())?;
            ev.ops.push(op);
            expect_operand = true;
        } else {
            return Err(CalcError::Syntax);
        }
        i += 1;
    }

    if expect_operand {
        return Err(CalcError::MissingOperand);
    }
    while let Some(&top) = ev.ops.last() {
        if top == StackOp::Open {
            return Err(CalcError::Unbalanced);
        }
        ev.reduce_top()?;
    }
    Ok(ev.pop_value())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, CalcError> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("2*(3+4)*5"), Ok(70));
    }

    #[test]
    fn division_and_remainder() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(CalcError::DivisionByZero));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
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
        assert_eq!(eval("000000000000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1 + 2\r", "-", ""] {
            assert!(eval(s).is_err(), "{s:?} should be an error");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 100_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&format!("{}1", "-".repeat(depth))), Ok(1));
    }
}
