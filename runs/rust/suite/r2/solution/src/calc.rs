//! 64-bit signed integer expression evaluator.
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! Evaluation uses an operator-precedence (shunting-yard) parser with explicit stacks, so deeply
//! nested input cannot overflow the call stack.

use std::fmt;
use std::io::{self, Write};

/// Evaluates each non-blank line of `input`, printing its value or `error`.
pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|&b| is_blank(b)) {
            continue;
        }
        match evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(_) => out.write_all(b"error\n")?,
        }
    }
    Ok(())
}

/// Why an expression has no value.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CalcError {
    Syntax,
    DivisionByZero,
    Overflow,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for CalcError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
    /// An open parenthesis: a barrier on the operator stack, never applied.
    Open,
}

impl Op {
    fn binary(byte: u8) -> Option<Self> {
        Some(match byte {
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
            Self::Open => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
            Self::Neg => 3,
        }
    }
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

/// Evaluates one expression.
pub fn evaluate(expr: &[u8]) -> Result<i64, CalcError> {
    let mut values: Vec<i64> = Vec::new();
    let mut ops: Vec<Op> = Vec::new();
    // True when the next token must start an operand (number, unary minus or '(').
    let mut expect_operand = true;
    let mut i = 0;

    while i < expr.len() {
        let byte = expr[i];
        if is_blank(byte) {
            i += 1;
            continue;
        }

        if expect_operand {
            match byte {
                b'0'..=b'9' => {
                    let (value, len) = parse_number(&expr[i..])?;
                    values.push(value);
                    i += len;
                    expect_operand = false;
                    continue;
                }
                b'-' => ops.push(Op::Neg),
                b'(' => ops.push(Op::Open),
                _ => return Err(CalcError::Syntax),
            }
        } else if byte == b')' {
            loop {
                match ops.pop() {
                    Some(Op::Open) => break,
                    Some(op) => apply(op, &mut values)?,
                    None => return Err(CalcError::Syntax),
                }
            }
        } else {
            let op = Op::binary(byte).ok_or(CalcError::Syntax)?;
            reduce(&mut ops, &mut values, op.precedence())?;
            ops.push(op);
            expect_operand = true;
        }
        i += 1;
    }

    if expect_operand {
        return Err(CalcError::Syntax);
    }
    while let Some(op) = ops.pop() {
        if op == Op::Open {
            return Err(CalcError::Syntax);
        }
        apply(op, &mut values)?;
    }
    match values.as_slice() {
        &[value] => Ok(value),
        _ => Err(CalcError::Syntax),
    }
}

/// Applies stacked operators that bind at least as tightly as `precedence` (left associativity).
fn reduce(ops: &mut Vec<Op>, values: &mut Vec<i64>, precedence: u8) -> Result<(), CalcError> {
    while let Some(&top) = ops.last() {
        if top == Op::Open || top.precedence() < precedence {
            break;
        }
        ops.pop();
        apply(top, values)?;
    }
    Ok(())
}

/// Parses the leading run of digits, returning its value and length.
fn parse_number(digits: &[u8]) -> Result<(i64, usize), CalcError> {
    let len = digits.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = digits[..len].iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|acc| acc.checked_add(i64::from(d - b'0')))
            .ok_or(CalcError::Overflow)
    })?;
    Ok((value, len))
}

fn apply(op: Op, values: &mut Vec<i64>) -> Result<(), CalcError> {
    let rhs = values.pop().ok_or(CalcError::Syntax)?;
    let result = if op == Op::Neg {
        rhs.checked_neg().ok_or(CalcError::Overflow)?
    } else {
        let lhs = values.pop().ok_or(CalcError::Syntax)?;
        binary(op, lhs, rhs)?
    };
    values.push(result);
    Ok(())
}

fn binary(op: Op, lhs: i64, rhs: i64) -> Result<i64, CalcError> {
    let overflow = CalcError::Overflow;
    match op {
        Op::Add => lhs.checked_add(rhs).ok_or(overflow),
        Op::Sub => lhs.checked_sub(rhs).ok_or(overflow),
        Op::Mul => lhs.checked_mul(rhs).ok_or(overflow),
        Op::Div if rhs == 0 => Err(CalcError::DivisionByZero),
        Op::Div => lhs.checked_div(rhs).ok_or(overflow),
        Op::Rem if rhs == 0 => Err(CalcError::DivisionByZero),
        // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
        Op::Rem => Ok(lhs.wrapping_rem(rhs)),
        Op::Neg | Op::Open => unreachable!("{op:?} is not a binary operator"),
    }
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
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("- (2 + 3) * 2"), Ok(-10));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("\t(\t(7)\t)"), Ok(7));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(CalcError::DivisionByZero));
        assert_eq!(eval("1 % 0"), Err(CalcError::DivisionByZero));
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
        assert_eq!(eval("3037000500 * 3037000500"), Err(CalcError::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 (2)", "(1)(2)", "1 - - ", "1\r", "* 2"] {
            assert_eq!(eval(s), Err(CalcError::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        assert_eq!(eval(&format!("{}1", "-".repeat(depth + 1))), Ok(-1));
    }

    #[test]
    fn blank_lines_print_nothing() {
        let mut out = Vec::new();
        run(b"\n  42  \n\t\n1+1\n1/0", &mut out).unwrap();
        assert_eq!(out, b"42\n2\nerror\n");
    }
}
