//! Evaluation of 64-bit signed integer expressions.
//!
//! Parsing uses an operator-precedence (shunting-yard) algorithm rather than
//! recursive descent, so deeply nested input cannot exhaust the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    /// A character outside the grammar, or a token in the wrong position.
    Syntax,
    /// A `(` without a matching `)`, or vice versa.
    UnbalancedParens,
    /// The expression ends where an operand is required.
    MissingOperand,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the `i64` range.
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let msg = match self {
            Self::Syntax => "syntax error",
            Self::UnbalancedParens => "unbalanced parentheses",
            Self::MissingOperand => "missing operand",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        };
        f.write_str(msg)
    }
}

impl std::error::Error for CalcError {}

/// An entry on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
    LParen,
}

impl Op {
    fn binary(byte: u8) -> Option<Self> {
        match byte {
            b'+' => Some(Self::Add),
            b'-' => Some(Self::Sub),
            b'*' => Some(Self::Mul),
            b'/' => Some(Self::Div),
            b'%' => Some(Self::Rem),
            _ => None,
        }
    }

    /// Binding strength; `None` for the parenthesis marker, which is never reduced.
    fn precedence(self) -> Option<u8> {
        match self {
            Self::Add | Self::Sub => Some(1),
            Self::Mul | Self::Div | Self::Rem => Some(2),
            Self::Neg => Some(3),
            Self::LParen => None,
        }
    }
}

fn apply_binary(op: Op, a: i64, b: i64) -> Result<i64, CalcError> {
    match op {
        Op::Add => a.checked_add(b).ok_or(CalcError::Overflow),
        Op::Sub => a.checked_sub(b).ok_or(CalcError::Overflow),
        Op::Mul => a.checked_mul(b).ok_or(CalcError::Overflow),
        Op::Div | Op::Rem if b == 0 => Err(CalcError::DivisionByZero),
        // Truncates toward zero; only `i64::MIN / -1` overflows.
        Op::Div => a.checked_div(b).ok_or(CalcError::Overflow),
        // Sign follows the dividend. `i64::MIN % -1` is mathematically 0,
        // which is exactly what the wrapping variant yields.
        Op::Rem => Ok(a.wrapping_rem(b)),
        Op::Neg | Op::LParen => unreachable!("{op:?} is not a binary operator"),
    }
}

/// Operand and operator stacks of the shunting-yard evaluator.
#[derive(Default)]
struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    fn pop_value(&mut self) -> i64 {
        self.values
            .pop()
            .expect("operand stack underflow: parser invariant violated")
    }

    /// Pops the top operator and applies it to the operand stack.
    fn reduce(&mut self) -> Result<(), CalcError> {
        let op = self.ops.pop().expect("reduce called with no operator");
        let result = if op == Op::Neg {
            self.pop_value().checked_neg().ok_or(CalcError::Overflow)?
        } else {
            let b = self.pop_value();
            let a = self.pop_value();
            apply_binary(op, a, b)?
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces operators until reaching a `(` (left in place) or an operator
    /// binding more loosely than `min_prec`.
    fn reduce_while(&mut self, min_prec: u8) -> Result<(), CalcError> {
        while let Some(prec) = self.ops.last().and_then(|op| op.precedence()) {
            if prec < min_prec {
                break;
            }
            self.reduce()?;
        }
        Ok(())
    }
}

/// Parses a run of ASCII digits as an `i64`, failing on overflow.
fn parse_literal(digits: &[u8]) -> Result<i64, CalcError> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })
}

const fn is_blank(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t')
}

/// Evaluates one expression.
pub fn evaluate(line: &[u8]) -> Result<i64, CalcError> {
    let mut ev = Evaluator::default();
    let mut expect_operand = true;
    let n = line.len();
    let mut i = 0;

    while i < n {
        let c = line[i];
        if is_blank(c) {
            i += 1;
            continue;
        }
        if expect_operand {
            if c.is_ascii_digit() {
                let len = line[i..].iter().take_while(|b| b.is_ascii_digit()).count();
                ev.values.push(parse_literal(&line[i..i + len])?);
                i += len;
                expect_operand = false;
                continue;
            }
            match c {
                b'-' => ev.ops.push(Op::Neg),
                b'(' => ev.ops.push(Op::LParen),
                _ => return Err(CalcError::Syntax),
            }
        } else if let Some(op) = Op::binary(c) {
            let prec = op.precedence().expect("binary operators have a precedence");
            ev.reduce_while(prec)?;
            ev.ops.push(op);
            expect_operand = true;
        } else if c == b')' {
            ev.reduce_while(0)?;
            if ev.ops.pop() != Some(Op::LParen) {
                return Err(CalcError::UnbalancedParens);
            }
        } else {
            return Err(CalcError::Syntax);
        }
        i += 1;
    }

    if expect_operand {
        return Err(CalcError::MissingOperand);
    }
    while let Some(&op) = ev.ops.last() {
        if op == Op::LParen {
            return Err(CalcError::UnbalancedParens);
        }
        ev.reduce()?;
    }
    Ok(ev.pop_value())
}

/// Returns `true` if the line is empty or holds only spaces and tabs.
pub fn is_blank_line(line: &[u8]) -> bool {
    line.iter().copied().all(is_blank)
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
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("1 - -2"), Ok(3));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(CalcError::Overflow));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(CalcError::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(CalcError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(CalcError::Overflow));
        assert_eq!(eval("0000000000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", "1\r", "-", ")"] {
            assert!(eval(s).is_err(), "{s:?} should fail");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 100_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&format!("{}7", "-".repeat(depth))), Ok(7));
    }
}
